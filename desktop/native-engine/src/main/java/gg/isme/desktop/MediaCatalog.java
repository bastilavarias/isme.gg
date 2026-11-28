package gg.isme.desktop;

import org.json.JSONArray;
import org.json.JSONObject;

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
 * Desktop source resolver port; requests run on the user's computer.
 * The previous TMDB server secret cannot be packaged into a public APK.
 */
final class MediaCatalog {
    static final String CINEMETA = "https://v3-cinemeta.strem.io";
    static final long MAX_BYTES = 7L * 1024 * 1024 * 1024;

    static JSONObject getJson(String address, int maxBytes) throws Exception {
        return getJson(address, maxBytes, 12000, 16000);
    }

    private static JSONObject getJson(String address, int maxBytes, int connectMs, int readMs) throws Exception {
        URL url = new URL(address);
        if (!"https".equalsIgnoreCase(url.getProtocol())) throw new IOException("HTTPS required");
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(connectMs);
        connection.setReadTimeout(readMs);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("User-Agent", "isme-desktop/1.0");
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
        String path = "/stream/" + (episodic ? "series" : "movie") + "/" + imdbId + ".json";
        return SourceProviders.firstAvailable(provider -> {
            JSONObject result = getJson(provider.base + path, 2 * 1024 * 1024, 4000, 6000);
            return parseSources(result, title, episodic);
        });
    }

    static List<Source> parseSources(JSONObject result, String title, boolean episodic) throws Exception {
        JSONArray streams = result.optJSONArray("streams");
        List<Source> found = new ArrayList<>();
        if (streams == null) return found;
        for (int i = 0; i < streams.length(); i++) {
            JSONObject stream = streams.optJSONObject(i);
            if (stream == null) continue;
            String hash = stream.optString("infoHash", "").toLowerCase(Locale.ROOT);
            if (!hash.matches("[a-f0-9]{40}")) continue;
            // Only accept direct torrent results, not debrid or HTTP playback links.
            if (!stream.optString("url", "").isEmpty() || !stream.optString("externalUrl", "").isEmpty()) continue;
            JSONObject hints = stream.optJSONObject("behaviorHints");
            String providerTitle = stream.optString("title", "");
            String description = stream.optString("description", "");
            String filename = hints == null ? "" : hints.optString("filename", "");
            String display = !providerTitle.isEmpty() ? providerTitle : !filename.isEmpty() ? filename : description;
            if (display.isEmpty()) display = stream.optString("name", "");
            String shortName = display.split("\\n", 2)[0];
            String release = display + "\n" + description + "\n" + stream.optString("name", "");
            // For episodic content the resolver key includes exact season and
            // episode; translated and alternate titles need not match the display title.
            if (!episodic&&!containsTitle(shortName, title)) continue;
            int fileIndex=episodic?stream.optInt("fileIdx",-1):-1;
            if(fileIndex < -1)continue;
            long bytes = hints == null ? -1 : hints.optLong("videoSize", -1);
            if (bytes <= 0) bytes = parseSize(release);
            // A pack can report aggregate size. The engine separately checks the
            // selected video's size and refuses ambiguous multi-file episodes.
            if (bytes > MAX_BYTES&&(!episodic||fileIndex<0)) continue;
            String quality = release.contains("720p") ? "720p"
                : release.contains("1080p") ? "1080p" : release.contains("480p") ? "480p" : "Unknown";
            if (release.toLowerCase(Locale.ROOT).matches("(?s).*(?:\\bcam\\b|telesync|hdcam).*")) continue;
            int seeders = 0;
            java.util.regex.Matcher seedMatch = java.util.regex.Pattern.compile("👤\\s*(\\d+)").matcher(release);
            if (seedMatch.find()) {
                try { seeders = Integer.parseInt(seedMatch.group(1)); }
                catch (NumberFormatException ignored) { seeders = 0; }
            }
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
        return q + codec + Math.min(45, src.seeders) * 2;
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
