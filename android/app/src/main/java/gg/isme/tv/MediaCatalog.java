package gg.isme.tv;

import org.json.JSONArray;
import org.json.JSONObject;
import android.content.Context;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

/**
 * Public, key-free Stremio metadata. Queries run on the TV, never on SEBASTECH.
 * The previous TMDB server secret cannot be packaged into a public APK.
 */
final class MediaCatalog {
    static final String CINEMETA = "https://v3-cinemeta.strem.io";
    static final String TORRENTIO = "https://torrentio.strem.fun";
    static final long MAX_BYTES = 3L * 1024 * 1024 * 1024;

    static JSONObject getJson(String address, int maxBytes) throws Exception {
        URL url = new URL(address);
        if (!"https".equalsIgnoreCase(url.getProtocol())) throw new IOException("HTTPS required");
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(12000);
        connection.setReadTimeout(16000);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("User-Agent", "isme-tv/1.0");
        try {
            if (connection.getResponseCode() != 200) throw new IOException("Provider HTTP " + connection.getResponseCode());
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            try (InputStream in = connection.getInputStream()) {
                byte[] b = new byte[8192];
                int n;
                while ((n = in.read(b)) != -1) {
                    if (bytes.size() + n > maxBytes) throw new IOException("Provider data too large");
                    bytes.write(b, 0, n);
                }
            }
            return new JSONObject(bytes.toString("UTF-8"));
        } finally { connection.disconnect(); }
    }

    static JSONObject catalog(Context app, String collection, String query) throws Exception {
        String url;
        if (query != null && !query.trim().isEmpty()) {
            url = CINEMETA + "/catalog/movie/top/search=" + encode(query.trim()) + ".json";
        } else {
            String suffix;
            switch (collection) {
                case "action": suffix = "top/genre=Action"; break;
                case "scifi": suffix = "top/genre=Sci-Fi"; break;
                case "horror": suffix = "top/genre=Horror"; break;
                case "top_rated": suffix = "imdbRating"; break;
                // TMDB snapshots generated with authenticated build tools, not on the TV.
                // Each entry carries IMDb ID so the local torrent engine can resolve it.
                case "pinoy":
                case "korean":
                case "english":
                    return bundledCatalog(app, collection);
                default: suffix = "top";
            }
            url = CINEMETA + "/catalog/movie/" + suffix + ".json";
        }
        JSONObject response = getJson(url, 1024 * 1024);
        JSONArray metas = response.optJSONArray("metas");
        JSONArray items = new JSONArray();
        if (metas != null) for (int i = 0; i < metas.length() && items.length() < 50; i++) {
            JSONObject meta = metas.optJSONObject(i);
            if (meta == null || !"movie".equals(meta.optString("type"))) continue;
            String imdb = meta.optString("id");
            String title = meta.optString("name");
            if (!imdb.matches("tt[0-9]{7,10}") || title.isEmpty()) continue;
            JSONObject movie = new JSONObject();
            movie.put("id", "imdb:" + imdb);
            movie.put("title", title);
            movie.put("type", "Movie");
            movie.put("description", meta.optString("description", ""));
            if (meta.optJSONArray("genres") != null) movie.put("genres", meta.optJSONArray("genres"));
            else if (meta.optJSONArray("genre") != null) movie.put("genres", meta.optJSONArray("genre"));
            if (!meta.isNull("runtime")) movie.put("runtime", meta.optString("runtime", ""));
            movie.put("year", meta.optString("releaseInfo", "").matches("^\\d{4}.*")
                ? Integer.parseInt(meta.optString("releaseInfo").substring(0, 4)) : JSONObject.NULL);
            movie.put("poster", meta.optString("poster", ""));
            movie.put("backdrop", meta.optString("background", ""));
            movie.put("available", false);
            items.put(movie);
        }
        return new JSONObject().put("items", items).put("source", "cinemeta")
            .put("page", 1).put("totalPages", 1).put("totalResults", items.length())
            .put("collection", collection).put("query", query == null ? "" : query);
    }

    private static JSONObject bundledCatalog(Context app, String collection) throws Exception {
        try (InputStream in = app.getAssets().open("catalogs/" + collection + ".json")) {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int n;
            while ((n = in.read(buffer)) != -1) {
                if (bytes.size() + n > 1024 * 1024) throw new IOException("Catalog snapshot too large");
                bytes.write(buffer, 0, n);
            }
            JSONObject result = new JSONObject(bytes.toString("UTF-8"));
            JSONArray items = result.optJSONArray("items");
            if (items == null || items.length() == 0)
                throw new IOException("No movies in " + collection + " catalog");
            return result;
        }
    }

    static final class Source {
        final String name, magnet, hash, quality;
        final int seeders, index, fileIndex;
        final long bytes;
        Source(String name, String magnet, String hash, String quality, int seeders, long bytes, int index) {
            this(name,magnet,hash,quality,seeders,bytes,index,-1);
        }
        Source(String name, String magnet, String hash, String quality, int seeders, long bytes, int index,int fileIndex) {
            this.name = name; this.magnet = magnet; this.hash = hash;
            this.quality = quality; this.seeders = seeders; this.bytes = bytes; this.index = index;
            this.fileIndex=fileIndex;
        }
        JSONObject publicJson() throws Exception {
            return new JSONObject().put("name", name).put("index", index)
                .put("quality", quality).put("seeders", seeders)
                .put("bytes", bytes > 0 ? bytes : JSONObject.NULL);
        }
    }

    static List<Source> resolve(String imdbId, String title) throws Exception {
        boolean episodic=imdbId.matches("tt[0-9]{7,10}:[0-9]{1,5}:[0-9]{1,5}");
        if (!episodic&&!imdbId.matches("tt[0-9]{7,10}")) throw new IOException("Invalid media ID");
        JSONObject result = getJson(TORRENTIO + "/stream/"+(episodic?"series":"movie")+"/" + imdbId + ".json", 2 * 1024 * 1024);
        JSONArray streams = result.optJSONArray("streams");
        List<Source> found = new ArrayList<>();
        if (streams == null) return found;
        for (int i = 0; i < streams.length(); i++) {
            JSONObject stream = streams.optJSONObject(i);
            if (stream == null) continue;
            String hash = stream.optString("infoHash", "").toLowerCase(Locale.ROOT);
            if (!hash.matches("[a-f0-9]{40}")) continue;
            String release = stream.optString("title", stream.optString("name", ""));
            String shortName = release.split("\\n")[0];
            // For episodic content the resolver key includes exact season and
            // episode; translated and alternate titles need not match the display title.
            if (!episodic&&!containsTitle(shortName, title)) continue;
            int fileIndex=episodic?stream.optInt("fileIdx",-1):-1;
            if(fileIndex < -1)continue;
            long bytes = parseSize(release);
            // A pack can report aggregate size. The engine separately checks the
            // selected video's size and refuses ambiguous multi-file episodes.
            if (bytes > MAX_BYTES&&(!episodic||fileIndex<0)) continue;
            String quality = release.contains("720p") ? "720p"
                : release.contains("1080p") ? "1080p" : release.contains("480p") ? "480p" : "Unknown";
            if (release.toLowerCase(Locale.ROOT).matches(".*(?:\\bcam\\b|telesync|hdcam).*")) continue;
            int seeders = 0;
            java.util.regex.Matcher seedMatch = java.util.regex.Pattern.compile("👤\\s*(\\d+)").matcher(release);
            if (seedMatch.find()) seeders = Integer.parseInt(seedMatch.group(1));
            String magnet = "magnet:?xt=urn:btih:" + hash;
            JSONArray trackers = stream.optJSONArray("sources");
            if (trackers != null) for (int j = 0; j < trackers.length() && j < 20; j++) {
                String src = trackers.optString(j, "");
                if (src.startsWith("tracker:")) {
                    String tr = src.substring(8);
                    if (tr.startsWith("udp://") || tr.startsWith("https://") || tr.startsWith("wss://"))
                        magnet += "&tr=" + encode(tr);
                }
            }
            if (magnet.indexOf("&tr=") < 0) magnet += "&tr=" + encode("udp://tracker.opentrackr.org:1337/announce");
            found.add(new Source(shortName, magnet, hash, quality, seeders, bytes, 0,fileIndex));
        }
        found.sort(Comparator.comparingInt(MediaCatalog::score).reversed());
        List<Source> resultList = new ArrayList<>();
        java.util.HashSet<String> seen = new java.util.HashSet<>();
        for (Source entry : found) {
            if (!seen.add(entry.hash+":"+entry.fileIndex)) continue;
            int idx = resultList.size();
            resultList.add(new Source(entry.name, entry.magnet, entry.hash, entry.quality,
                entry.seeders, entry.bytes, idx,entry.fileIndex));
            if (resultList.size() == 16) break;
        }
        return resultList;
    }

    private static int score(Source src) {
        int q = "720p".equals(src.quality) ? 100 : "1080p".equals(src.quality) ? 85 :
            "480p".equals(src.quality) ? 40 : 0;
        int codec = src.name.matches("(?i).*(?:x265|hevc|av1|hdr).*") ? -50 : 0;
        if (src.name.toLowerCase(Locale.ROOT).contains("mp4")) codec += 12;
        return q + codec + Math.min(90, src.seeders * 2);
    }

    private static boolean containsTitle(String release, String title) {
        if (title == null || title.trim().isEmpty()) return true;
        String a = release.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", " ");
        String b = title.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", " ").trim();
        return (" " + a + " ").contains(" " + b + " ");
    }

    private static long parseSize(String release) {
        java.util.regex.Matcher m = java.util.regex.Pattern
            .compile("([0-9]+(?:\\.[0-9]+)?)\\s*(GiB|GB|MiB|MB)", java.util.regex.Pattern.CASE_INSENSITIVE)
            .matcher(release);
        if (!m.find()) return -1;
        double v = Double.parseDouble(m.group(1));
        String unit = m.group(2).toLowerCase(Locale.ROOT);
        double multiplier = unit.startsWith("gi") ? Math.pow(1024, 3) :
            unit.startsWith("g") ? Math.pow(1000, 3) :
            unit.startsWith("mi") ? Math.pow(1024, 2) : Math.pow(1000, 2);
        return (long) (v * multiplier);
    }

    static String encode(String value) throws Exception {
        return URLEncoder.encode(value, StandardCharsets.UTF_8.name());
    }
}
