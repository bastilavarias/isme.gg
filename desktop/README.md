# isme.gg Desktop — cinematic milestone

Development branch: desktop/foundation. Separate Flutter package; released Android TV and mobile clients remain untouched. This is a source implementation, not a verified release.

## Design

The desktop home prioritizes real, large-format artwork: a manually browsable featured title with restrained crossfades, readable synopsis, responsive poster shelves, Continue Watching, Filipino and Korean cinema snapshots, and My List. Movie/series/search pages retain a responsive grid. Poster controls use the shared dark/warm orange palette, reveal on hover or keyboard focus, and respect reduced motion. Selecting a title opens a full-page cinematic detail view, with season/episode navigation for series.

## Playback

The Java sidecar ports the existing libtorrent4j 2.1.0-39 engine, storage budget and verified-piece reader. It runs as a child process on the local computer, binds only to 127.0.0.1 on an ephemeral port, and requires a fresh 256-bit token for control and byte ranges. The Flutter player uses media_kit with the private authenticated URL. The source picker, retry, mascot, per-episode resume and recent watch shelf are wired. Local video selection remains available. No hosted media relay or uploaded cache. Use media you are authorized to access; source availability is not guaranteed. The source resolver is shared in behavior with Android but copied for this milestone; future changes must reconcile the two implementations.

The sidecar is stopped when the player closes; the parent removes only its own session directory after process exit. Abrupt termination can leave an abandoned temporary directory. No automatic deletion of other sessions is attempted. The 7 GiB selected-file limit and native storage checks remain in place. No production rolling-cache claim.

## Windows development (do not run until build approved)

From the repository root, with pinned Flutter/Dart, Visual Studio C++ toolchain, JDK 21 and Maven:

- `.\setupdesktop.ps1` launches the shell using a prepared engine if available.
- `.\setupdesktop.ps1 -Engine` prepares the Java sidecar, then launches.
- `.\setupdesktop.ps1 -Test` runs Flutter analysis and widget tests; no public distribution.
- `.\setupdesktop.ps1 -Build` compiles/tests native and Flutter code, then copies native dependencies and a jlink runtime into the release bundle.

Release directory: desktop/build/windows/x64/runner/Release/. Keep the entire folder together. The optional Inno Setup recipe in packaging/windows.iss is for a later explicitly authorized installer build; it has not been compiled or signed. The user should not need Flutter, Maven or Visual Studio to run a validated packaged bundle.

The desktop CI workflow runs only for an explicit desktop/build-* branch push or a supported manual dispatch; desktop/foundation changes no longer launch builds automatically. No public release.

## Linux and macOS (experimental)

`bash desktop/setup-unix.sh run|test|build` provisions a generated runner for the current OS, prepares the Maven sidecar and optionally bundles the Java runtime. Existing platform prerequisites must already be installed; the script does not install packages. Linux currently targets the x64 Flutter output layout. macOS sandbox behavior, JNI architecture, signing/notarization and native library loading remain unverified. Do not distribute unsigned or untested bundles.

## Validation before public release

- Compile the native engine, run range unit tests, run Flutter analyzer and widget tests, and verify runner and dependency lock reproducibility.
- On Windows, test resize, keyboard focus, hover/reduced motion, real artwork, navigation, saved titles, series/episode selection, local video, and fullscreen.
- On authorized seeded test media, measure startup, verified range reads, seek, buffer, source switching, timeouts, progress persistence, cancellation, stale sessions, process exit and cache cleanup. Test authentication failures and native binaries.
- Verify portable bundle on a clean Windows machine without Java/Flutter/Visual Studio; test installer, licensing notices and required VC runtime.
- Validate Linux and macOS separately; macOS signing and entitlements need real-machine checks.

Still pending: production-grade desktop update channel and signing, release dependency lock, full Android catalog/provider metadata parity, episode auto-preparation, adaptive buffering, SQLite migration, robust crash recovery and all runtime/platform checks. No claim of production parity. Do not bump Android version or merge to main before desktop validation.
