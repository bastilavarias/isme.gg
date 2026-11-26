# Fixed source provider fallback

Discovery runs directly on the Android device, in this order:

1. Torrentio
2. MediaFusion (public Midnight instance)
3. Comet (developer's public instance)
4. Peerflix

The resolver stops at the first provider with compatible sources. Empty results, invalid responses, HTTP errors (including rate limits), and timeouts fall through to the next provider. Each lookup uses a 4-second connection timeout and a 6-second read timeout; these are socket timeouts, not a guaranteed overall deadline. No account, debrid service, self-hosted instance, or SEBASTECH service is required by the implementation.

The common parser accepts direct torrent hashes only, supports title/description/filename fields, preserves episode file indices and existing source filtering, ranking and deduplication. The existing playback recovery logic remains unchanged: it retries candidates from the selected provider, not later providers once that candidate list has been returned. Next-episode preparation uses the same resolver.

## Verification

The public manifest checks succeeded for all three alternatives. A single metadata lookup for the openly licensed Blender film Big Buck Bunny returned direct torrent entries from Torrentio, MediaFusion and Comet; Peerflix responded with an empty list. This is not an uptime or playback guarantee. Public endpoints can change, enforce rate limits, or withdraw access; confirm provider usage policies before public release.

Run the JVM regression test using a Java 17+ compiler, an Android platform jar, and org.json 20240303:

```sh
CP=/path/to/json-20240303.jar:/path/to/android.jar
javac --release 17 -cp "$CP" -d /tmp/isme-provider-tests \
  android/app/src/main/java/gg/isme/tv/SourceProviders.java \
  android/app/src/main/java/gg/isme/tv/MediaCatalog.java \
  tools/SourceProvidersTest.java
java -cp "/tmp/isme-provider-tests:$CP" gg.isme.tv.SourceProvidersTest
```

The test covers primary short-circuit, network errors, empty responses, fixed priority including the last fallback, total failure, interruption, direct torrent filtering, duplicate removal, provider metadata formats, and episode file indices. No media downloads are needed.

Before release: verify real Android TV and mobile playback with authorized media, next-episode preparation, slow/disconnected networks, and provider-specific episodic responses. Full APK build and on-device playback are not covered by the JVM test.
