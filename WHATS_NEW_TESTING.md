# What's New — v0.2.0 QA

The installed Android versionName and versionCode identify the registered release. Android package timestamps distinguish a first install from an upgrade. On first launch of an eligible build, a shared Flutter dialog appears after the home route mounts; update prompts are held until it closes. An acknowledgment is saved only after Continue and successful preference writes. Closing the process before confirmation allows the dialog to appear on next launch. No network call is required for content or acknowledgment. Fresh installs receive a welcome heading; updates receive a success heading.

## Windows emulator
1. Pull main and run `setupwindows.bat -Mobile -ReuseEmulator` or `setupwindows.bat -TV -ReuseEmulator`. Do not uninstall or clear data to test an upgrade.
2. Confirm v0.2.0 appears. Both checkboxes start unchecked for users on Legacy HTTP; existing experimental choices are preselected. Fast Startup depends on Native Direct.
3. Continue without opt-in; verify Settings > Experimental playback says Legacy HTTP. Restart the app; no repeat modal.
4. In the debug app, Settings > Support & about > Preview What's New opens the update variant again without resetting acknowledgment. This preview really applies preferences on Continue. Enable Native Direct alone, then verify Fast Startup off and Adaptive Buffering on. Preview again, check both, and verify both on. Return to Legacy HTTP through Settings or by unchecking Native Direct in the preview.
5. Test touch, TV directional keys/Select, disabled Fast Startup focus, short-height landscape and scrollable content. Confirm the orange focus/controls remain usable, Back does not accidentally acknowledge, and only Continue writes selections. Test existing watch history and bookmarks survive.
6. Test authorized video playback with each transport. The direct provider is available in both debug and release, still non-exported, no URI grants, read-only and same-UID checked. The experiments are optional, no new engine scheduling algorithm or automatic fallback. If direct is incompatible, switch manually to Legacy HTTP.
7. On a signed ARM release candidate, upgrade from v0.1.0 and repeat. No public release until separately authorized.

Each future release needs owner-approved content, its own builder and a matching version+versionCode registry entry; release CI rejects missing/reused builders. The registration check enforces structure, not actual owner approval.
