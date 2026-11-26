# Development and release toolchain

Use one canonical Windows checkout and one shared main branch. Keep tracked Gradle configuration portable across Windows and CI.

## Shared versions

`toolchain.json` is the version contract. GitHub Actions reads it when provisioning Flutter and Java; both Windows and CI validate Gradle, Android Gradle Plugin, Kotlin and compile SDK against it. Upgrade the contract and shared Gradle files together. The pinned versions are Flutter 3.38.10, JDK 21, Gradle 8.13, AGP 8.13.1, Kotlin 2.2.21 and Android SDK/Build Tools 36/36.0.0.

Install the exact Flutter version from https://docs.flutter.dev/install/archive and JDK 21 from https://adoptium.net/temurin/releases/. In Android Studio install Android API 36 and Build Tools 36.0.0. The SDK may live anywhere outside the project. If not automatically found, set the local environment variable ISME_FLUTTER_DIR or pass -FlutterDir to the launcher. Use ISME_JDK_DIR or -JdkDir for JDK discovery.

## Windows startup

From the original project root, first verify that existing local tracked changes have been reviewed and reconciled. Do not delete work, run a hard reset, automatically stash, or create another checkout to bypass this requirement. If local fixes are useful, integrate and test them as shared code.

```bat
setupwindows.bat -CheckOnly
setupwindows.bat -Both -ReuseEmulator
```

The launcher only fast-forwards a clean main checkout. It refuses local-only commits, mismatched SDK versions, and dirty tracked files. It verifies the checkout at each preparation stage and on exit. It never rewrites tracked configuration to adapt to the machine. Wrapper scripts and jar are generated from a temporary scaffold using the pinned SDK; only ignored outputs are copied. That temporary scaffold is deleted. For CI and troubleshooting, -BuildOnly -SkipPull performs a debug compile without emulators.

Machine-specific settings remain in ignored files: android/local.properties (SDK paths), android/metadata.properties (TMDB key or read token), android/key.properties (release signing), and Android/Flutter build caches. Keep credentials and signing files local. A public APK credential can still be extracted.

## CI checks

The Android development checks workflow runs on Windows with the same launcher in build-only mode. It compiles, runs Flutter analysis/tests and Python regression tests, and checks that no tracked source files changed. The release workflow consumes the same pins and checks the checkout after preparation, tests and signed compilation. Neither development check publishes an APK.

The launcher and release workflow enforce the tracked `pubspec.lock`. CI also uploads the resolved lockfile for review.

## Acceptance

A successful Windows CI run and real local tests on TV and mobile are required. After stopping the launcher, run `git status --short --untracked-files=no`; it must print nothing. Repeat the build and verify a subsequent upstream fast-forward. If a tool modifies tracked files, record the first reported stage and inspect that exact diff without exposing credentials. Fix the shared build configuration once, not with local patches or blanket ignores. No signing, API keys, or user emulator data should be reset.
