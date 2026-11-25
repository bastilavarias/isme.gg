# isme.gg Flutter edition (0.3.0 development)
Independent source project at /home/sebastech/projects/ismegg. Original React/WebView project is unchanged.
This is an implementation draft, not a verified build. Flutter, Dart, JDK and Gradle are not available on the server PATH. No APK was compiled or installed there. Android compilation, physical TV navigation, subtitles and native playback still need verification on Windows.

## Windows setup
1. Install Flutter stable (Dart >=3.6), Android Studio, SDK 35, compatible JDK 17+ and platform tools. Run flutter doctor -v and flutter doctor --android-licenses.
2. From PowerShell copy the source (same LAN, SSH access required):
   `scp -r sebastech@192.168.1.109:/home/sebastech/projects/ismegg .`
3. `cd ismegg`, `flutter pub get`, `flutter analyze`, `flutter test`.
4. Connect Android TV or phone with USB or wireless debugging; use `adb devices -l`, `flutter devices`, then `flutter run -d DEVICE_ID`. If a Gradle wrapper is not provisioned by Flutter, run .\tools\prepare-windows.ps1 first. No wrapper binary is checked into this source.
5. Press r for Dart hot reload; Java changes need a restart/rebuild. Compare performance using `flutter run --profile -d DEVICE_ID`, not debug. Optional local test APK: `flutter build apk --debug`. Output: build/app/outputs/flutter-apk/app-debug.apk.
6. Side-by-side debug app ID gg.isme.tv.flutter.debug. Existing v0.2.0 app and data are not modified. Do not uninstall original app. Production migration/signing is not configured.

## Architecture
- Dart UI: home (focus-driven background on TV), lazy poster shelves, details, search, manual authorized magnet, native video controller, history and captions.
- Native Java bridge starts authenticated HTTP service bound to 127.0.0.1 only; no bundled web UI, no WebView or runtime server host. Uses existing libtorrent4j, MediaCatalog, SubtitleSupport and ReleaseUpdater, with three bundled language catalogs. Native video_player Android backend uses ExoPlayer/Media3, subject to dependency resolution.
- HTTP requests use a random per-process X-Isme-Token; range requests allow normal open-ended Media3 reads. Media pieces temporarily reside in app-private cache. External metadata/source/subtitle providers remain dependencies. Play only content you are authorized to access and test with legally shared media.
- Player switches subtitle caption files on the same controller (no planned seek/reinitialize), supports play/pause, seek, source selection, resume and cancellation. Existing provider availability/codec issues are not solved by migration.
- Original UI reference and orange/dark theme, independent Flutter widgets; no third-party clone source or assets imported because exact file licensing/dependencies were not audited.
- Dependencies are provisional version constraints; lockfile and exact Android Gradle compatibility must be resolved on Windows. Riverpod deferred in favor of simple local state for first pass. Native updater code retained but intentionally disabled until repository and signing are configured. No automatic update or release signing yet. Audio track selection and subtitle timing adjustment remain follow-ups.
- Native method channel is used for connection and update action; on-device HTTP polling for existing engine state (not a full typed event-channel migration).
## Validation checklist
Run flutter analyze/test and compile on Windows. Verify TV launcher and D-pad navigation, focus after back, phone rotation and landscape controls, catalog and search, authorized test video startup/seek/subtitles, no position reset on caption switch, stop and cache cleanup, crash recovery, and memory/frame times over repeated playback. Check ARM64 and ARMv7 devices. Profile on the physical TV before claiming performance gains. No release cutover until these pass.
