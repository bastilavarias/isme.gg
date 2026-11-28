# isme.gg desktop preview

Experimental separate Flutter package in the isme.gg repository. Android builds and native Android playback are unchanged. This is the first desktop milestone, not a public release.

## Windows

Prerequisites: pinned Flutter and Dart from the root toolchain.json, Visual Studio with Desktop development with C++, and Windows desktop support. Reuse ISME_FLUTTER_DIR or Flutter on PATH.

From repository root:

```powershell
.\setupdesktop.ps1
.\setupdesktop.ps1 -Test
.\setupdesktop.ps1 -Build
```

The launcher prepares the existing Poppins assets, generates the Windows runner in desktop/ when missing, resolves desktop dependencies, and launches or tests the desktop application. The build mode runs analysis/tests before producing an unsigned portable development build. Runner files and desktop lockfile are provisional generated artifacts; commit reproducible runner configuration and a resolved lockfile before a public release. Never ship only the exe: DLLs and data/ must travel with it.

## Linux (experimental)

Use the pinned Flutter SDK and distro Flutter Linux prerequisites plus the media_kit/libmpv runtime dependencies documented upstream. From the repository root run dart tools/prepare_fonts.dart, then in desktop/ run flutter create --platforms=linux --project-name ismegg_desktop --org gg.isme --no-pub --empty . followed by flutter pub get and flutter run -d linux. Linux packaging is not validated.

## Implemented source

- Responsive desktop sidebar: Home, Movies, Series, Search, My List. Compact icon rail below 1000 logical pixels, scrollable navigation.
- Live Cinemeta metadata from the same service already used by Android. No fabricated titles; no media availability claim. Movie/series search, title details, loading, retry and empty states.
- Responsive poster grid, hover feedback, keyboard focus/activation and reduced-motion support. Shared Movie model, CinemaColors and CinemaArt.
- Local My List persistence in a desktop-only preference key.
- Native local file picker and in-app media_kit playback for user-selected video files. Adaptive desktop controls provide playback controls and fullscreen; test these on real Windows.
- Ctrl+K: search. Ctrl+O: open local video. Ctrl+R: refresh. Tab/Enter: navigate and activate. Playback controls provided by media_kit.

## Not implemented yet

Online torrent playback, portable libtorrent4j sidecar, native source discovery, next episode, platform availability metadata, continue watching, production SQLite storage, desktop updater, signing, installers, macOS support. The catalog is metadata-only and explicitly states that online playback is not connected. The local-file player does not silently resolve or fetch title sources.

Next milestone: extract Android-independent Java catalog/torrent components behind the existing authenticated loopback protocol, implement OS-specific storage and credential adapters, package native binaries, validate cancellation/seek/cleanup with authorized test media, then connect desktop player to that interface. Preserve client-only processing and keep Android regression checks independent. Review libmpv and native binary distribution licenses before public packaging.

## Validation

Desktop test source covers catalog parsing, navigation, resize, detail dialog and persisted saved titles. Desktop CI workflow generates the runner, runs Flutter analyzer and widget tests, then builds a Windows artifact; does not publish. Manual checks: resize small/large windows, keyboard focus, reduced motion, real network loading, local video opening, seek, audio, fullscreen/exit, cancellation, closing/reopening. No SDK on SEBASTECH; actual compilation, rendering, dependency resolution, and playback need Windows/CI validation.
