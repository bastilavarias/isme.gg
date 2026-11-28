package gg.isme.desktop;

import java.io.IOException;
import java.util.Collections;
import java.util.List;

/** Fixed, client-side discovery priority. Never query a lower provider after success. */
final class SourceProviders {
    enum Provider {
        TORRENTIO("https://torrentio.strem.fun"),
        MEDIAFUSION("https://mediafusionfortheweebs.midnightignite.me"),
        COMET("https://comet.feels.legal"),
        PEERFLIX("https://peerflix.mov");

        final String base;
        Provider(String base) { this.base = base; }
    }

    interface Lookup<T> {
        List<T> resolve(Provider provider) throws Exception;
    }

    static <T> List<T> firstAvailable(Lookup<T> lookup) throws Exception {
        boolean responded = false;
        for (Provider provider : Provider.values()) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedException();
            try {
                List<T> sources = lookup.resolve(provider);
                if (Thread.currentThread().isInterrupted()) throw new InterruptedException();
                responded = true;
                if (sources != null && !sources.isEmpty()) return sources;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw e;
            } catch (Exception unavailable) {
                // A network error, rate limit or invalid response must not
                // prevent the next independent provider from being tried.
            }
        }
        if (!responded) throw new IOException("Media source providers unavailable");
        return Collections.emptyList();
    }

    private SourceProviders() {}
}
