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
        listener = new ServerSocket();
        // Fixed only in explicit debug mode so Windows adb forward can access the
        // on-device torrent API without rebuilding the APK for Vite changes.
        listener.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), devMode ? 8210 : 0));
        acceptThread = new Thread(this::serve, "isme-local-http");
        acceptThread.setDaemon(true);
        acceptThread.start();
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
        try {
            if (path.equals("/health")) {
                sendJson(out, 200, new JSONObject().put("ok", true).put("engine", "android-native")
                    .put("origin", "localhost")); return;
            }
            if (path.equals("/api/catalog") && method.equals("GET")) {
                sendJson(out, 200, MediaCatalog.catalog(context, query.getOrDefault("collection", "trending"),
                    query.getOrDefault("query", ""))); return;
            }
            if (path.equals("/api/status") && method.equals("GET")) {
                sendJson(out, 200, torrents.state()); return;
            }
            if (path.equals("/api/play") && method.equals("POST")) {
                JSONObject body = new JSONObject(new String(data, StandardCharsets.UTF_8));
                String id = body.optString("id", "");
                String magnet = body.optString("magnet", "");
                if (!id.matches("imdb:tt[0-9]{7,10}") && magnet.isEmpty()) {
                    sendJson(out, 422, new JSONObject().put("error", "Unsupported movie ID")); return;
                }
                subtitles.reset();
                torrents.start(id, body.optString("title", id), body.optInt("sourceIndex", 0), magnet);
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
            if (path.equals("/stream/video") && (method.equals("GET") || method.equals("HEAD"))) {
                streamVideo(out, headers.get("range"), method.equals("HEAD")); return;
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

    private void streamVideo(OutputStream out, String range, boolean head) throws Exception {
        long size = torrents.movieSize();
        if (size <= 0) {
            sendJson(out, 409, new JSONObject().put("error", "Movie not ready")); return;
        }
        long start = 0, end = size - 1;
        boolean partial = range != null && !range.isEmpty();
        if (partial) {
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("^bytes=(\\d+)-(\\d*)$")
                .matcher(range);
            if (!m.matches()) {
                rawHeaders(out, 416, "Range Not Satisfiable", "text/plain", 0,
                    "Content-Range: bytes */" + size + "\r\n"); return;
            }
            start = Long.parseLong(m.group(1));
            if (start >= size) {
                rawHeaders(out, 416, "Range Not Satisfiable", "text/plain", 0,
                    "Content-Range: bytes */" + size + "\r\n"); return;
            }
            end = m.group(2).isEmpty() ? size - 1 : Math.min(size - 1, Long.parseLong(m.group(2)));
            if (end < start) {
                rawHeaders(out, 416, "Range Not Satisfiable", "text/plain", 0,
                    "Content-Range: bytes */" + size + "\r\n"); return;
            }
        } else end = size - 1;
        long contentLength = end - start + 1;
        String extra = "Accept-Ranges: bytes\r\n" + (partial
            ? "Content-Range: bytes " + start + "-" + end + "/" + size + "\r\n" : "");
        rawHeaders(out, partial ? 206 : 200, partial ? "Partial Content" : "OK",
            torrents.mimeType(), contentLength, extra);
        if (!head) torrents.writeRange(start, end, out);
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
        torrents.stop();
        try { listener.close(); } catch (IOException ignored) {}
        workers.shutdownNow();
    }
}
