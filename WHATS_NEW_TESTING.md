# What's New — v2.0.1 QA

The installed Android versionName and versionCode identify the registered release. Android package timestamps distinguish a first install from an upgrade. On first launch of an eligible build, a shared Flutter dialog appears after the home route mounts; update prompts are held until it closes. An acknowledgment is saved after Continue or Back; the dialog does not write playback preferences. Closing the process before confirmation allows the dialog to appear on next launch. No network call is required for content or acknowledgment. Fresh installs receive a welcome heading; updates receive a success heading.

## Windows emulator
1. Pull main and run `setupwindows.bat -Mobile -ReuseEmulator` or `setupwindows.bat -TV -ReuseEmulator`. Do not uninstall or clear data to test an upgrade.
2. Confirm v2.0.1 appears with a single focused Continue button, no checkboxes, and playback status matching current preferences.
3. On a clean install, verify Native Direct and Fast Startup default on. For an upgrade with saved settings, verify those settings are unchanged. Restart the app; no repeat modal after dismissal.
4. In the debug app, Settings > Support & about > Preview What's New opens the update variant again without changing acknowledgment or preferences. Change transport and Fast Startup through Settings; confirm the preview reflects the chosen values.
5. Test touch, TV Select/Enter, Back, short-height landscape and scrollable content. Confirm Continue is clearly focused and either Select or Back closes only the modal. Test existing watch history and bookmarks survive.
6. Test authorized video playback with each transport. The direct provider is available in both debug and release, still non-exported, no URI grants, read-only and same-UID checked. The experiments are optional, no new engine scheduling algorithm or automatic fallback. If direct is incompatible, switch manually to Legacy HTTP.
7. On a signed ARM release candidate, upgrade from v0.2.0 and repeat. No public release until separately authorized.

Each future release needs owner-approved content, its own builder and a matching version+versionCode registry entry; release CI rejects missing/reused builders. The registration check enforces structure, not actual owner approval.
