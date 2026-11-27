# Native Direct benchmark (debug only)

The current HTTP transport remains default. Settings > Experimental playback > Playback transport selects Legacy HTTP or Native Direct. It applies to the next playback. Release builds ignore the preference and do not register the direct provider.

## Implementation
Native Direct reuses the pinned Flutter video_player / Android Media3 integration via VideoPlayerController.contentUri. A non-exported debug-only ContentProvider exposes a read-only seekable Android StorageManager proxy descriptor. Requests are served by a bounded number of worker threads and the same TorrentEngine selected-file cache. Reads check generation, cancellation and verified piece availability before copying bytes. File length and EOF respect the selected video, including multi-file piece boundaries. The provider does not expose paths or grant permissions. Switching or leaving playback cancels active direct readers before disposing the decoder. Legacy HTTP remains unchanged.

This is an alternative native transport using Media3's existing content data source, not a bespoke Media3 DataSource or a rolling cache. The loopback HTTP control/catalog API remains. The same 7 GiB limit, storage guards, source selection, recovery budget, and 45-second initialization timeout remain. Direct reads have a 35-second bounded wait per callback, and may still fail if the media data is not available. FUSE support, seek performance, cancellation and kernel read behavior on specific Android devices must be validated. No guaranteed performance improvement. No transparent fallback within an experimental attempt: select Legacy HTTP manually to keep the comparison clear.

## Benchmark
1. Use a debug build and identical authorized media on the same physical device. If possible use the exact same source and start position. Run modes sequentially, not simultaneously. Record 3–5 cold starts per mode.
2. Use the Settings selector to switch modes. Start a fresh playback each time. Capture IsmePlayback, IsmeDirect, IsmeTorrent, IsmeLocalServer and ExoPlayer logs separately.
3. The start line identifies transport, attempt and candidate index; initialization line reports selected file bytes, elapsed readiness and HTTP probe times (null for direct). The playing line reports initialization, play request and first observed forward position change. Timings are cumulative within each attempt, not true first rendered frame; firstAdvanceMs is sampled every two seconds. Use wall-clock timing to first visible frame and include failed attempts when comparing total startup.
4. Inspect direct read slow/failed logs with offset, bytes and waitMs. Test seek backward/forward, resume, subtitles/audio, repeated open/close, next episode and low storage. Verify cleanup and no stale session data. Repeat on ARM64 phone and real Android TV; emulator is functional coverage only.
5. Do not publish or make direct the default without passing runtime tests and reviewing measurements.
