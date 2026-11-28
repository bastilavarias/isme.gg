package gg.isme.desktop;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.concurrent.*;
import java.util.regex.*;

/** Private loopback sidecar. One process and one cache per player. */
public final class DesktopServer {
    private final TorrentEngine engine;
    private final HttpServer server;
    private final String token;
    private final ExecutorService workers = Executors.newFixedThreadPool(8);
    private DesktopServer(File cache, String token) throws IOException {
        this.token = token;
        engine = new TorrentEngine(cache);
        server = HttpServer.create(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0), 16);
        server.setExecutor(workers);
        server.createContext("/", this::handle);
    }
    public static void main(String[] args) throws Exception {
        String token = System.getenv("ISME_DESKTOP_TOKEN");
        String cache = System.getenv("ISME_DESKTOP_CACHE");
        if (token == null || !token.matches("[a-f0-9]{64}") || cache == null)
            throw new IllegalArgumentException("Missing private session configuration");
        Path path = Path.of(cache).toRealPath(LinkOption.NOFOLLOW_LINKS);
        if (Files.isSymbolicLink(path) || !Files.isDirectory(path) ||
            !path.getFileName().toString().startsWith("isme-session-"))
            throw new IllegalArgumentException("Invalid private cache");
        try (var entries = Files.list(path)) {
            if (entries.findAny().isPresent()) throw new IllegalArgumentException("Cache must be empty");
        }
        DesktopServer app = new DesktopServer(path.toFile(), token);
        Runtime.getRuntime().addShutdownHook(new Thread(app::close));
        app.server.start();
        System.out.println(new JSONObject().put("port", app.server.getAddress().getPort()).put("protocol", 1));
        System.out.flush();
        // The parent owns stdin. EOF closes this server even after parent failure.
        try { while (System.in.read() != -1) {} } finally { app.close(); }
        System.exit(0);
    }
    private synchronized void close() {
        server.stop(0);
        engine.stop();
        workers.shutdownNow();
    }
    private boolean authorized(HttpExchange ex) {
        String header = ex.getRequestHeaders().getFirst("x-isme-token");
        return header != null && MessageDigest.isEqual(token.getBytes(StandardCharsets.US_ASCII),
            header.getBytes(StandardCharsets.US_ASCII));
    }
    private void handle(HttpExchange ex) {
        try {
            if (!authorized(ex)) { empty(ex, 403); return; }
            String method = ex.getRequestMethod(), path = ex.getRequestURI().getPath();
            if ("GET".equals(method) && "/api/state".equals(path)) {
                json(ex, 200, engine.state());
            } else if ("POST".equals(method) && "/api/start".equals(path)) {
                byte[] bytes = ex.getRequestBody().readNBytes(32769);
                if (bytes.length > 32768) { empty(ex, 413); return; }
                JSONObject body = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
                String id = body.optString("id"), title = body.optString("title"), magnet = body.optString("magnet");
                String episode = body.optString("episode");
                int index = body.optInt("source", 0);
                if (id.length() > 100 || title.length() > 512 || magnet.length() > 16000 || index < 0 || index > 15 ||
                    (magnet.isEmpty() && !id.matches("imdb:tt[0-9]{7,10}")) ||
                    (!episode.isEmpty() && !episode.matches("tt[0-9]{7,10}:[0-9]{1,5}:[0-9]{1,5}"))) {
                    empty(ex, 400); return;
                }
                engine.start(id, title, index, magnet, episode, true, false);
                json(ex, 200, new JSONObject().put("accepted", true));
            } else if ("POST".equals(method) && "/api/stop".equals(path)) {
                engine.stop(); json(ex, 200, new JSONObject().put("stopped", true));
            } else if (("GET".equals(method) || "HEAD".equals(method)) && "/stream/video".equals(path)) {
                stream(ex, "HEAD".equals(method));
            } else empty(ex, 404);
        } catch (Exception failure) {
            // Do not append JSON once media headers have been sent.
            try { if (ex.getResponseCode() == -1) empty(ex, 500); } catch (IOException ignored) {}
        } finally { ex.close(); }
    }
    static long[] range(String header, long size) {
        if (size <= 0) throw new IllegalArgumentException("Invalid size");
        if (header == null) return new long[]{0, size - 1};
        Matcher m = Pattern.compile("^bytes=(\\d*)-(\\d*)$").matcher(header);
        if (!m.matches() || (m.group(1).isEmpty() && m.group(2).isEmpty())) throw new IllegalArgumentException("Invalid range");
        long start = 0, end = size - 1;
        if (m.group(1).isEmpty()) {
            long suffix = Long.parseLong(m.group(2));
            if (suffix <= 0) throw new IllegalArgumentException("Invalid suffix");
            start = Math.max(0, size - suffix);
        } else {
            start = Long.parseLong(m.group(1));
            if (!m.group(2).isEmpty()) end = Math.min(end, Long.parseLong(m.group(2)));
        }
        if (start >= size || end < start) throw new IllegalArgumentException("Unsatisfiable range");
        return new long[]{start, end};
    }
    private void stream(HttpExchange ex, boolean head) throws Exception {
        long generation = engine.generation();
        if (!("session=" + generation).equals(ex.getRequestURI().getRawQuery())) { empty(ex, 410); return; }
        long size = engine.movieSize();
        if (size <= 0 || !"ready".equals(engine.state().optString("status"))) { empty(ex, 409); return; }
        String header = ex.getRequestHeaders().getFirst("Range");
        long[] span;
        try { span = range(header, size); } catch (IllegalArgumentException failure) {
            ex.getResponseHeaders().set("Content-Range", "bytes */" + size); empty(ex, 416); return;
        }
        if (generation != engine.generation()) { empty(ex, 410); return; }
        long count = span[1] - span[0] + 1;
        ex.getResponseHeaders().set("Content-Type", engine.mimeType());
        ex.getResponseHeaders().set("Cache-Control", "no-store");
        ex.getResponseHeaders().set("Accept-Ranges", "bytes");
        if (header != null) ex.getResponseHeaders().set("Content-Range", "bytes " + span[0] + "-" + span[1] + "/" + size);
        if (head) ex.getResponseHeaders().set("Content-Length", Long.toString(count));
        ex.sendResponseHeaders(header == null ? 200 : 206, head ? -1 : count);
        if (!head) engine.writeRange(span[0], span[1], generation, ex.getResponseBody());
    }
    private static void empty(HttpExchange ex, int code) throws IOException { ex.sendResponseHeaders(code, -1); }
    private static void json(HttpExchange ex, int code, JSONObject data) throws IOException {
        byte[] bytes = data.toString().getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        ex.getResponseHeaders().set("Cache-Control", "no-store");
        ex.sendResponseHeaders(code, bytes.length);
        ex.getResponseBody().write(bytes);
    }
}
