# Playback Engine V2 — incremental reliability milestone

## Implemented foundation (not a rolling cache)
- Keep the existing authenticated loopback origin, verified-piece reads, package ID, signing, Flutter player and 3 GiB selected-file cap.
- StorageBudget reserves 5% of the cache volume, clamped to 256 MiB–1 GiB, plus 64 MiB write headroom. Before opening a session, require another 64 MiB of available capacity. After metadata resolution, require the complete selected video to fit above that reserve; this is intentionally conservative and does not assume sparse-file allocation saves physical space.
- Sample available storage every second on the native session thread monitor, even while the player is paused. Stop the matching session if the headroom is exhausted, invalidate the generation, and clean up after native stop succeeds. Monitoring is best-effort, not an atomic reservation: concurrent apps or writes between checks can still fill storage.
- Low-storage errors are non-retryable device errors and display a free-space message. Existing files and metadata databases are not deleted by the storage guard.
- Native monotonic timestamps report resolution, metadata and first-piece readiness. Flutter records readiness observation, successful byte-range validation, player initialization, play request and first observed forward position change. These are elapsed milliseconds per attempt; native and Flutter clocks have different starting points. Position advancement is sampled every two seconds and is **not** actual rendered-first-frame timing.
- Startup readiness polling is reduced from 850 ms to 250 ms. Keep the bounded range probe, existing timeouts and verified reads. This is a responsiveness change, not a measured startup improvement or an event-driven implementation.
- Diagnostics are local debug UI only; no remote telemetry, media, provider URLs, magnet hashes or credentials are exported.

## Remaining phases and gates
1. Establish real startup, rebuffering, decoder, seek, storage and cleanup measurements using authorized test media. Use a native first-frame event rather than position sampling for accurate startup metrics.
2. Investigate a native readiness event channel; cancellation and stale generation tests must pass before replacing polling.
3. Prototype Media3 buffer profiles independently of disk caching. The current video_player integration does not expose all LoadControl options. Do not claim adaptive buffering until native adapter and benchmarks are verified.
4. Inspect the exact libtorrent4j 2.1.0-39 JNI bindings for custom disk I/O and verified-piece lifecycle support. If absent, isolate native extension research in a separate worktree. A fixed buffer budget requires safe accounting, coordination of in-flight reads/writes and verified-piece eviction; never delete bytes behind the engine's back.
5. A bounded cache prototype is not ready for production until it passes long sessions, random seeks, backward seeks outside its window, integrity validation, multi-file boundaries, cancellation, concurrent cleanup, pressure and ARMv7/ARM64 compatibility. Keep the existing path until then.

## Tests
- Run StorageBudgetTest with Java 17+ (compile StorageBudget.java and tools/StorageBudgetTest.java, then run gg.isme.tv.StorageBudgetTest).
- Run flutter analyze and flutter test; Android development checks build the debug APK.
- On real Android TV and phone: check low-storage rejection before session creation and after metadata; simulate external storage pressure during playback and pause, verify clean stop and resume progress; inspect free space before/after repeated retries, Back, completion and force-stop/relaunch. Ensure My List/history/settings remain intact.
- Compare startup on identical authorized media and controlled networks; record cold/warm starts separately. Measure actual first-frame time, rebuffering ratio, seek latency and cache allocation; avoid reporting whole-file logical length as allocated bytes.
- No release version bump or publishing is part of this milestone.
