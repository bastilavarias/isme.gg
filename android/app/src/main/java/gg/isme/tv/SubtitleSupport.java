package gg.isme.tv;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Remote subtitle metadata and SRT to WebVTT conversion, fetched on-device. */
final class SubtitleSupport {
    private String lastImdb = "";
    private JSONArray rows = new JSONArray();

    synchronized JSONObject tracks(String imdb) throws Exception {
        if (!imdb.matches("tt[0-9]{7,10}")) return new JSONObject().put("tracks", new JSONArray());
        if (!imdb.equals(lastImdb)) {
            JSONObject data = MediaCatalog.getJson(
                "https://opensubtitles-v3.strem.io/subtitles/movie/" + imdb + ".json", 2 * 1024 * 1024);
            JSONArray incoming = data.optJSONArray("subtitles");
            JSONArray valid = new JSONArray();
            if (incoming != null) for (int i = 0; i < incoming.length() && valid.length() < 150; i++) {
                JSONObject item = incoming.optJSONObject(i);
                if (item != null && allowed(item.optString("url")) &&
                    item.optString("lang").matches("[a-z]{2,3}")) valid.put(item);
            }
            rows = valid;
            lastImdb = imdb;
        }
        JSONArray publicItems = new JSONArray();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject item = rows.getJSONObject(i);
            String lang = item.optString("lang", "eng");
            String label = "eng".equals(lang) ? "English" : "fil".equals(lang) ? "Filipino" :
                "tgl".equals(lang) ? "Tagalog" : "kor".equals(lang) ? "Korean" : lang.toUpperCase(Locale.ROOT);
            publicItems.put(new JSONObject()
                .put("id", i).put("lang", lang).put("label", label)
                .put("name", item.optString("subtitleFileName", "Subtitle"))
                .put("origin", "OpenSubtitles").put("score", 0));
        }
        return new JSONObject().put("tracks", publicItems);
    }

    synchronized byte[] subtitle(int id, double offsetSeconds) throws Exception {
        if (id < 0 || id >= rows.length() || Math.abs(offsetSeconds) > 30)
            throw new IOException("Invalid subtitle selection");
        String address = rows.getJSONObject(id).optString("url");
        if (!allowed(address)) throw new IOException("Subtitle URL rejected");
        HttpURLConnection connection = (HttpURLConnection) new URL(address).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(15000);
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try {
            if (connection.getResponseCode() != 200) throw new IOException("Subtitle service unavailable");
            try (InputStream in = connection.getInputStream()) {
                byte[] chunk = new byte[4096];
                int n;
                while ((n = in.read(chunk)) != -1) {
                    if (buffer.size() + n > 768 * 1024) throw new IOException("Subtitle too large");
                    buffer.write(chunk, 0, n);
                }
            }
        } finally { connection.disconnect(); }
        String raw = buffer.toString("UTF-8").replace("\r\n", "\n").replace("\r", "\n");
        String vtt = raw.startsWith("WEBVTT") ? raw : "WEBVTT\n\n" + raw;
        Pattern time = Pattern.compile("(\\d{2}:\\d{2}:\\d{2})[,.](\\d{3})");
        Matcher m = time.matcher(vtt);
        StringBuffer shifted = new StringBuffer();
        while (m.find()) {
            String[] hms = m.group(1).split(":");
            long ms = (((Long.parseLong(hms[0]) * 60 + Long.parseLong(hms[1])) * 60
                + Long.parseLong(hms[2])) * 1000 + Long.parseLong(m.group(2)));
            ms = Math.max(0, ms + Math.round(offsetSeconds * 1000));
            long hours = ms / 3600000, minutes = (ms / 60000) % 60;
            long seconds = (ms / 1000) % 60, remainder = ms % 1000;
            m.appendReplacement(shifted, String.format(Locale.ROOT, "%02d:%02d:%02d.%03d",
                hours, minutes, seconds, remainder));
        }
        m.appendTail(shifted);
        return shifted.toString().getBytes(StandardCharsets.UTF_8);
    }

    synchronized void reset() { rows = new JSONArray(); lastImdb = ""; }

    private static boolean allowed(String value) {
        try {
            URL url = new URL(value);
            return "https".equals(url.getProtocol())
                && url.getHost().matches("(?i)subs[0-9]+\\.strem\\.io")
                && url.getPath().startsWith("/en/download/")
                && url.getUserInfo() == null
                && value.length() < 1024;
        } catch (Exception error) { return false; }
    }
}
