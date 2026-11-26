# Development and release toolchain

Use your normal Windows checkout. Keep tracked Gradle configuration portable across Windows and CI.

## Shared versions

[`toolchain.json`](toolchain.json) is the version contract for Windows and both Android workflows. It specifies Flutter and its bundled Dart SDK, Java, Gradle, Android Gradle Plugin, Kotlin, and Android SDK and Build Tools. Update the contract, shared Gradle files and tracked dependency lockfile together when upgrading Flutter.

Use the specified [Flutter SDK](https://docs.flutter.dev/install/archive) and [Temurin JDK](https://adoptium.net/temurin/releases/). Install the specified Android SDK Platform and Build Tools in Android Studio. The launcher can find Flutter on `PATH`, through `ISME_FLUTTER_DIR`, or with `-FlutterDir`. Use `ISME_JDK_DIR` or `-JdkDir` for JDK discovery.

The tracked `android/gradle.properties` declares the AGP DSL and Kotlin compatibility options used by the current plugins. Flutter adds these properties automatically when they are missing, so both the Windows launcher and CI check them before building.

The app defines ABI filters by build type. Debug supports ARM and x86_64 emulators, and the signed release APK targets ARM64 and ARMv7.

## Windows startup

From the project root, use the launcher to run the TV and mobile AVDs named in the script. You can override their names with `-TvAvd` and `-MobileAvd`.

```bat
setupwindows.bat -CheckOnly
setupwindows.bat -Both -ReuseEmulator
```

The launcher fast-forwards a clean `main` when possible. It builds local changes and local commits in place, and stops if the Git index contains an unresolved conflict. It checks for new tracked changes during preparation and compilation, and checks tracked build configuration when the Flutter session exits. Any changes it reports stay on disk.

In both-device mode, the launcher builds one debug APK and gives it to Flutter to install and run on both emulators. Use `r` to hot reload, `R` to hot restart, and `q` to stop the session. The pinned SDK supplies the ignored Gradle wrapper scripts and JAR through a temporary scaffold. CI and troubleshooting can use `-BuildOnly -SkipPull` for the same debug compile without emulators.

Machine-specific settings remain in ignored files: android/local.properties (SDK paths), android/metadata.properties (TMDB key or read token), android/key.properties (release signing), and Android/Flutter build caches. Keep credentials and signing files local. A public APK credential can still be extracted.

## CI checks

The Android development checks workflow runs on Windows with the same launcher in build-only mode. It compiles, runs Flutter analysis/tests and Python regression tests, and checks that no tracked source files changed. The release workflow consumes the same pins and checks the checkout after preparation, tests and signed compilation. Neither development check publishes an APK.

The launcher and release workflow enforce the tracked `pubspec.lock`. CI also uploads the resolved lockfile for review.

## Acceptance

Run `setupwindows.bat -Both -ReuseEmulator` and confirm the app starts on TV and mobile. Quit with `q` and repeat. In both runs, the launcher should report that it preserved tracked build configuration. Compare Git status and diff before and after the runs to confirm they show the same local changes. In CI, the checkout should remain clean.
