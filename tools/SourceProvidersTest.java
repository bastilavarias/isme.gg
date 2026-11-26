package gg.isme.tv;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

public final class SourceProvidersTest {
    private static void require(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }

    private static final String HASH = "0123456789abcdef0123456789abcdef01234567";

    public static void main(String[] args) throws Exception {
        List<SourceProviders.Provider> visits = new ArrayList<>();
        List<String> primary = SourceProviders.firstAvailable(provider -> {
            visits.add(provider);
            return Collections.singletonList("primary");
        });
        require(primary.equals(Collections.singletonList("primary")), "primary result");
        require(visits.equals(Collections.singletonList(SourceProviders.Provider.TORRENTIO)), "primary short-circuit");

        visits.clear();
        List<String> fallback = SourceProviders.firstAvailable(provider -> {
            visits.add(provider);
            switch (provider) {
                case TORRENTIO: throw new IOException("timeout");
                case MEDIAFUSION: return Collections.emptyList();
                case COMET: return Collections.singletonList("fallback");
                default: throw new AssertionError("Peerflix should not be queried");
            }
        });
        require(fallback.equals(Collections.singletonList("fallback")), "Comet fallback");
        require(visits.equals(Arrays.asList(SourceProviders.Provider.TORRENTIO,
            SourceProviders.Provider.MEDIAFUSION, SourceProviders.Provider.COMET)), "fixed order");

        visits.clear();
        List<String> last = SourceProviders.firstAvailable(provider -> {
            visits.add(provider);
            return provider == SourceProviders.Provider.PEERFLIX
                ? Collections.singletonList("last") : Collections.emptyList();
        });
        require(last.equals(Collections.singletonList("last")), "Peerflix last fallback");
        require(visits.equals(Arrays.asList(SourceProviders.Provider.values())), "all four in order");

        require(SourceProviders.firstAvailable(provider -> Collections.emptyList()).isEmpty(), "all empty");
        try {
            SourceProviders.firstAvailable(provider -> { throw new IOException("unavailable"); });
            throw new AssertionError("all failed must throw");
        } catch (IOException expected) { }
        try {
            SourceProviders.firstAvailable(provider -> { throw new InterruptedException(); });
            throw new AssertionError("cancellation must propagate");
        } catch (InterruptedException expected) {
            require(Thread.interrupted(), "interrupt restored");
        }

        JSONObject p2p = new JSONObject().put("name", "MediaFusion 1080p")
            .put("description", "WEBRip\n500 MB 👤 7").put("infoHash", HASH)
            .put("behaviorHints", new JSONObject().put("filename", "Big.Buck.Bunny.1080p.mp4")
                .put("videoSize", 500000000L));
        JSONObject http = new JSONObject(p2p.toString()).put("url", "https://example.org/video");
        JSONObject other = new JSONObject(p2p.toString()).put("infoHash", "bad");
        JSONObject cam = new JSONObject(p2p.toString()).put("description", "WEBRip\nHDcam");
        JSONObject payload = new JSONObject().put("streams", new JSONArray()
            .put(http).put(other).put(cam).put(p2p).put(p2p));
        List<MediaCatalog.Source> parsed = MediaCatalog.parseSources(payload, "Big Buck Bunny", false);
        require(parsed.size() == 1, "deduplicate, filter non-P2P and invalid hash/cam");
        require(parsed.get(0).quality.equals("1080p") && parsed.get(0).seeders == 7 &&
            parsed.get(0).bytes == 500000000L && parsed.get(0).index == 0, "fallback metadata");

        JSONObject torrentio = new JSONObject().put("name", "Torrentio 720p")
            .put("title", "Big Buck Bunny 720p\n👤 10 250 MB").put("infoHash", HASH);
        parsed = MediaCatalog.parseSources(new JSONObject().put("streams", new JSONArray().put(torrentio)), "Big Buck Bunny", false);
        require(parsed.size() == 1 && parsed.get(0).quality.equals("720p") &&
            parsed.get(0).seeders == 10, "primary format unchanged");

        JSONObject episode = new JSONObject().put("description", "Open Series S01E02 720p\n200 MB")
            .put("name", "Comet 720p").put("infoHash", HASH).put("fileIdx", 2);
        parsed = MediaCatalog.parseSources(new JSONObject().put("streams", new JSONArray().put(episode)),
            "Episode 2", true);
        require(parsed.size() == 1 && parsed.get(0).fileIndex == 2, "episode file index retained");

        require(MediaCatalog.parseSources(new JSONObject(), "Open Movie", false).isEmpty(), "empty payload");
        System.out.println("PASS: fixed priority, short-circuit, fallback, cancellation and source parsing");
    }
}
