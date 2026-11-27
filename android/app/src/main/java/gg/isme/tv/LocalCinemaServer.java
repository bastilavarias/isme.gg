package gg.isme.tv;

import android.content.Context;


import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Ephemeral loopback HTTP origin: authenticated on-device torrent API
 * + HTTP 206 video. Never listens on LAN and never proxies video to a host.
 */
final class LocalCinemaServer {
    private final Context context;
    private final TorrentEngine torrents;
    private final CatalogCache metadata;
    private final WatchProviders providers;
    private final SeriesCatalog series;
    private final PlatformCatalog platforms;
    private final HomeCatalog home;
    private final SubtitleSupport subtitles = new SubtitleSupport();
    private final ExecutorService workers = Executors.newFixedThreadPool(8);
    private final ServerSocket listener;
    private final String token = java.util.UUID.randomUUID().toString();
    String token() { return token; }
    private volatile boolean running = true;
    private final Thread acceptThread;

    LocalCinemaServer(Context context, boolean devMode) throws Exception {
        this.context = context.getApplicationContext();
        this.torrents = new TorrentEngine(context.getCacheDir());
        this.metadata = new CatalogCache(this.context);
        this.providers = new WatchProviders(metadata);
        this.series = new SeriesCatalog(metadata);
        this.platforms = new PlatformCatalog(metadata);
        this.home = new HomeCatalog(metadata);
        listener = new ServerSocket();
        // Fixed only in explicit debug mode so Windows adb forward can access the
        // on-device torrent API without rebuilding the APK for Vite changes.
        listener.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), devMode ? 8210 : 0));
        acceptThread = new Thread(this::serve, "isme-local-http");
        acceptThread.setDaemon(true);
        acceptThread.start();
        DirectMediaProvider.bind(torrents);
    }

    String url() { return "http://127.0.0.1:" + listener.getLocalPort() + "/"; }

    private void serve() {
        while (running) {
            try {
                Socket socket = listener.accept();
                workers.execute(() -> {
                    try (Socket close = socket) {
                        close.setSoTimeout(30000);
                        handle(close);
                    } catch (Exception error) {
                        android.util.Log.w("IsmeLocalServer", "HTTP client disconnected: " + error.getClass().getSimpleName());
                    }
                });
            } catch (IOException e) {
                if (running) android.util.Log.e("IsmeLocalServer", "Accept failed", e);
            }
        }
    }

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        int next;
        while ((next = in.read()) != -1) {
            if (next == '\n') break;
            if (next != '\r') bytes.write(next);
            if (bytes.size() > 8192) throw new IOException("HTTP line too long");
        }
        return bytes.toString("UTF-8");
    }

    private void handle(Socket client) throws Exception {
        BufferedInputStream in = new BufferedInputStream(client.getInputStream());
        OutputStream out = client.getOutputStream();
        String first = readLine(in);
        if (first.trim().isEmpty()) return;
        String[] request = first.split(" ");
        if (request.length < 2 || !request[0].matches("GET|HEAD|POST")) {
            sendJson(out, 405, new JSONObject().put("error", "Method not allowed")); return;
        }
        String method = request[0];
        String target = request[1];
        if (!target.startsWith("/") || target.length() > 4096) {
            sendJson(out, 400, new JSONObject().put("error", "Bad request")); return;
        }
        Map<String, String> headers = new HashMap<>();
        for (int i = 0; i < 55; i++) {
            String header = readLine(in);
            if (header.isEmpty()) break;
            int colon = header.indexOf(':');
            if (colon > 0) headers.put(header.substring(0, colon).trim().toLowerCase(Locale.ROOT),
                header.substring(colon + 1).trim());
        }

        if (!token.equals(headers.get("x-isme-token"))) {
            sendJson(out, 403, new JSONObject().put("error", "Forbidden")); return;
        }
        int size = 0;
        try { size = Integer.parseInt(headers.getOrDefault("content-length", "0")); }
        catch (NumberFormatException ignored) {}
        if (size < 0 || size > 12000) {
            sendJson(out, 413, new JSONObject().put("error", "Body too large")); return;
        }
        byte[] data = new byte[size];
        int offset = 0;
        while (offset < size) {
            int n = in.read(data, offset, size - offset);
            if (n < 1) throw new IOException("Incomplete HTTP body");
            offset += n;
        }
        String path = target.split("\\?", 2)[0];
        Map<String, String> query = parseQuery(target);
        if (path.equals("/stream/video") && (method.equals("GET") || method.equals("HEAD"))) {
            streamVideo(out, headers.get("range"), method.equals("HEAD"), query.get("session")); return;
        }
        try {
            if (path.equals("/health")) {
                sendJson(out, 200, new JSONObject().put("ok", true).put("engine", "android-native")
                    .put("origin", "localhost")); return;
            }
            if (path.equals("/api/catalog") && method.equals("GET")) {
                sendJson(out, 200, metadata.catalog(context, query.getOrDefault("collection", "trending"),
                    query.getOrDefault("query", ""), query.getOrDefault("mode", "normal"))); return;
            }
            if (path.equals("/api/home/catalog") && method.equals("POST")) {
                JSONObject body=new JSONObject(new String(data,StandardCharsets.UTF_8));
                sendJson(out,200,home.catalog(body.optString("collection",""),body.optString("mode","normal"),body.optString("token","")));return;
            }
            if (path.equals("/api/providers") && method.equals("POST")) {
                JSONObject body = new JSONObject(new String(data, StandardCharsets.UTF_8));
                sendJson(out, 200, providers.lookup(body.optString("imdb",""),
                    body.optInt("tmdbId",0),body.optString("country",""),body.optString("token",""),body.optBoolean("tv",false))); return;
            }
            if (path.equals("/api/tv/catalog") && method.equals("POST")) {
                JSONObject body = new JSONObject(new String(data, StandardCharsets.UTF_8));
                sendJson(out,200,series.catalog(body.optString("collection","series"),body.optString("query","").trim(),body.optString("mode","normal"),body.optString("token","")));return;
            }
            if (path.equals("/api/tv/seasons") && method.equals("POST")) {
                JSONObject body = new JSONObject(new String(data, StandardCharsets.UTF_8));
                sendJson(out,200,series.seasons(body.optString("id"),body.optString("token","")));return;
            }
            if (path.equals("/api/tv/episodes") && method.equals("POST")) {
                JSONObject body = new JSONObject(new String(data, StandardCharsets.UTF_8));
                sendJson(out,200,series.episodes(body.optString("id"),body.optInt("season",-1),body.optString("token","")));return;
            }
            if(path.equals("/api/platforms")&&method.equals("POST")){
                JSONObject body=new JSONObject(new String(data,StandardCharsets.UTF_8));
                sendJson(out,200,platforms.directory(body.optString("country","PH"),body.optString("token",""),body.optString("mode","normal")));return;
            }
            if(path.equals("/api/platform/catalog")&&method.equals("POST")){
                JSONObject body=new JSONObject(new String(data,StandardCharsets.UTF_8));
                sendJson(out,200,platforms.discover(body.optString("country","PH"),body.optString("ids",""),
                    body.optString("kind","movie"),body.optString("row","popular"),body.optString("mode","normal"),body.optString("token","")));return;
            }
            if(path.equals("/api/platform/movie-id")&&method.equals("POST")){
                JSONObject body=new JSONObject(new String(data,StandardCharsets.UTF_8));
                sendJson(out,200,new JSONObject().put("imdb",platforms.movieImdb(body.optInt("tmdbId",0),body.optString("token",""))));return;
            }
            if (path.equals("/api/status") && method.equals("GET")) {
                JSONObject state = torrents.state();
                if (BuildConfig.DEBUG && "ready".equals(state.optString("status"))) {
                    String stream = state.optString("streamUrl");
                    if (stream.startsWith("/stream/video?session=")) {
                        long generation = Long.parseLong(stream.substring("/stream/video?session=".length()));
                        android.net.Uri direct = DirectMediaProvider.uri(context, torrents, generation);
                        if (direct != null) state.put("directUri", direct.toString());
                    }
                }
                sendJson(out, 200, state); return;
            }
            if(path.equals("/api/next/prepare")&&method.equals("POST")){
                JSONObject body=new JSONObject(new String(data,StandardCharsets.UTF_8));
                String current=body.optString("currentId",""),next=body.optString("id","");
                java.util.regex.Pattern pattern=java.util.regex.Pattern.compile("^(imdb:tt[0-9]{7,10}|tmdb:tv:[1-9][0-9]{0,8}):s([0-9]{1,5}):e([0-9]{1,5})$");
                java.util.regex.Matcher a=pattern.matcher(current),b=pattern.matcher(next);
                if(!a.matches()||!b.matches()||!a.group(1).equals(b.group(1))||
                    Integer.parseInt(b.group(2))<Integer.parseInt(a.group(2))||
                    (a.group(2).equals(b.group(2))&&Integer.parseInt(b.group(3))<=Integer.parseInt(a.group(3)))){
                    sendJson(out,422,new JSONObject().put("error","Invalid next episode"));return;
                }
                final String parent=b.group(1),suffix=":"+b.group(2)+":"+b.group(3);
                final String access=body.optString("tmdbToken",""),name=body.optString("title",next);
                boolean accepted=torrents.prepareNext(current,next,()->MediaCatalog.resolve(series.imdbId(parent,access)+suffix,name));
                sendJson(out,200,new JSONObject().put("accepted",accepted));return;
            }
            if(path.equals("/api/next/cancel")&&method.equals("POST")){
                JSONObject body=new JSONObject(new String(data,StandardCharsets.UTF_8));
                torrents.cancelNext(body.optString("currentId",""));
                sendJson(out,200,new JSONObject().put("ok",true));return;
            }
            if (path.equals("/api/play") && method.equals("POST")) {
                JSONObject body = new JSONObject(new String(data, StandardCharsets.UTF_8));
                String id = body.optString("id", "");
                String magnet = body.optString("magnet", "");
                java.util.regex.Matcher episode=java.util.regex.Pattern.compile("^(imdb:tt[0-9]{7,10}|tmdb:tv:[1-9][0-9]{0,8}):s([0-9]{1,5}):e([0-9]{1,5})$").matcher(id);
                String episodeKey="";
                if(magnet.isEmpty()&&episode.matches()){
                    episodeKey=series.imdbId(episode.group(1),body.optString("tmdbToken",""))+":"+episode.group(2)+":"+episode.group(3);
                }else if (!id.matches("imdb:tt[0-9]{7,10}") && magnet.isEmpty()) {
                    sendJson(out, 422, new JSONObject().put("error", "Unsupported media ID")); return;
                }
                subtitles.reset();
                torrents.start(id, body.optString("title", id), body.optInt("sourceIndex", 0), magnet,episodeKey,
                    BuildConfig.DEBUG && body.optBoolean("fastStartup", false));
                sendJson(out, 202, new JSONObject().put("status", "loading")); return;
            }
            if (path.equals("/api/stop") && method.equals("POST")) {
                torrents.stop();
                subtitles.reset();
                sendJson(out, 200, new JSONObject().put("status", "idle")); return;
            }
            if (path.equals("/api/subtitles") && method.equals("GET")) {
                sendJson(out, 200, subtitles.tracks(torrents.currentImdbId())); return;
            }
            if (path.equals("/api/subtitle") && method.equals("GET")) {
                int id = Integer.parseInt(query.getOrDefault("id", "-1"));
                double seconds = Double.parseDouble(query.getOrDefault("offset", "0"));
                byte[] captions = subtitles.subtitle(id, seconds);
                rawHeaders(out, 200, "OK", "text/vtt; charset=utf-8", captions.length, "");
                out.write(captions);
                out.flush();
                return;
            }
            if (!method.equals("GET") && !method.equals("HEAD")) {
                sendJson(out, 405, new JSONObject().put("error", "Method not allowed")); return;
            }
            sendJson(out, 404, new JSONObject().put("error", "Not found"));
        } catch (Exception failure) {
            String detail = failure.getMessage() == null ? "Request failed" : failure.getMessage();
            sendJson(out, 502, new JSONObject().put("error", detail));
        }
    }

    private static Map<String, String> parseQuery(String target) throws Exception {
        Map<String, String> values = new HashMap<>();
        int index = target.indexOf('?');
        if (index < 0) return values;
        for (String p : target.substring(index + 1).split("&")) {
            String[] pair = p.split("=", 2);
            if (pair.length == 2 && pair[0].length() < 50)
                values.put(pair[0], URLDecoder.decode(pair[1], "UTF-8"));
        }
        return values;
    }

    private void streamVideo(OutputStream out, String range, boolean head, String requestedSession) throws Exception {
        final long generation = torrents.generation();
        if (requestedSession != null && !Long.toString(generation).equals(requestedSession)) {
            rawHeaders(out, 410, "Gone", "text/plain", 0, ""); return;
        }
        long size = torrents.movieSize();
        if (size <= 0) {
            rawHeaders(out, 409, "Conflict", "text/plain", 0, ""); return;
        }
        long start = 0, end = size - 1;
        boolean partial = range != null && !range.isEmpty();
        if (partial) {
            try {
                java.util.regex.Matcher m = java.util.regex.Pattern.compile("^bytes=(\\d*)-(\\d*)$").matcher(range);
                if (!m.matches() || (m.group(1).isEmpty() && m.group(2).isEmpty()))
                    throw new IllegalArgumentException("Invalid range");
                if (m.group(1).isEmpty()) {
                    long suffix = Long.parseLong(m.group(2));
                    if (suffix <= 0) throw new IllegalArgumentException("Invalid suffix");
                    start = Math.max(0, size - suffix);
                } else {
                    start = Long.parseLong(m.group(1));
                    if (!m.group(2).isEmpty()) end = Math.min(end, Long.parseLong(m.group(2)));
                }
                if (start >= size || end < start) throw new IllegalArgumentException("Unsatisfiable range");
            } catch (IllegalArgumentException e) {
                rawHeaders(out, 416, "Range Not Satisfiable", "text/plain", 0,
                    "Content-Range: bytes */" + size + "\r\n"); return;
            }
        }
        String mime = torrents.mimeType();
        if (generation != torrents.generation()) {
            rawHeaders(out, 410, "Gone", "text/plain", 0, ""); return;
        }
        String extra = "Accept-Ranges: bytes\r\n" + (partial
            ? "Content-Range: bytes " + start + "-" + end + "/" + size + "\r\n" : "");
        rawHeaders(out, partial ? 206 : 200, partial ? "Partial Content" : "OK",
            mime, end - start + 1, extra);
        // Once headers are sent, close on failure instead of appending JSON to media bytes.
        if (!head) torrents.writeRange(start, end, generation, out);
    }

    private static void sendJson(OutputStream out, int code, JSONObject json) throws IOException {
        byte[] bytes = json.toString().getBytes(StandardCharsets.UTF_8);
        rawHeaders(out, code, code == 200 ? "OK" : "Error", "application/json; charset=utf-8", bytes.length, "");
        out.write(bytes);
        out.flush();
    }

    private static void rawHeaders(OutputStream out, int code, String reason, String mime, long size,
            String extra) throws IOException {
        String value = "HTTP/1.1 " + code + " " + reason + "\r\n"
            + "Content-Type: " + mime + "\r\n"
            + "Content-Length: " + size + "\r\n"
            + "Connection: close\r\n"
            + "Cache-Control: no-store\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Content-Security-Policy: default-src 'self'; img-src 'self' https: data:; media-src 'self' blob:; "
            + "connect-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
            + "font-src 'self' data:; object-src 'none'; base-uri 'none'\r\n"
            + extra + "\r\n";
        out.write(value.getBytes(StandardCharsets.US_ASCII));
    }

    void close() {
        running = false;
        DirectMediaProvider.unbind(torrents);
        torrents.stop();
        try { listener.close(); } catch (IOException ignored) {}
        workers.shutdownNow();
        metadata.close();
    }
}
