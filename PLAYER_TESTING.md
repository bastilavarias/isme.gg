# Player controls and track-selection regression checklist

Source changes only; no compilation or device tests performed on SEBASTECH.
Requires Flutter 3.38+/Dart 3.10+, Android SDK 36, JDK 17, Gradle 8.13 / AGP 8.13.1 and Kotlin 2.2.21. Target SDK remains 35. The audio API uses video_player 2.11.1 and its Android implementation 2.9.1, pinned to avoid unrelated major Android build changes. Resolve dependencies and validate compilation on Windows.

Use owned or otherwise authorized test clips with known formats and subtitles.

1. Run flutter pub get, flutter analyze, flutter test, then flutter run. The dependency and Android build changes require a full restart/rebuild locally, not just hot reload.
2. Play media. Wait more than six seconds for controls to hide. Press D-pad center, up, or down. Controls should return, Play/Pause should receive focus, and subsequent D-pad presses must move between controls. Left/right while hidden should seek ten seconds and reveal controls. Dedicated media keys should work without first opening the overlay. Test repeated keys and Back.
3. Open subtitles or audio with the TV remote. The menu should immediately appear with a loading state if necessary, remain open beyond six seconds, and support directional navigation and center selection. After dismissing it, controls should regain focus.
4. Check automatic subtitles: preferred language, English fallback, then any available track. Confirm Off persists for subsequent playback and source recovery. Confirm manual switching does not seek or reload media. Subtitle discovery should never delay initial playback. External provider availability and timing are not guaranteed.
5. Audio: use a multi-track authorized test clip with same-language AAC stereo and surround audio; verify automatic compatibility preference, manual selection, restoring automatic preference, and uninterrupted position. No transcoding or synthesized track is provided. An unsupported device or unavailable track must not block video playback.
6. Verify player debug overlay lists the currently selected audio track when available. Compare static noise with the same authorized stereo clip on emulator and physical Android TV; capture Logcat for actual audio underruns and decoder errors. No audio-static fix is claimed without testing.
7. Test prior carousel, layout overflow and recovery changes. Do not overwrite local Windows-only emulator adaptations. Server checkout has not been pushed or compiled.
