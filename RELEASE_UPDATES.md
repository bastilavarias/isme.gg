# isme.gg GitHub Releases updater

## Status
Source implementation only. SEBASTECH does not have the Android/Flutter toolchain; no signed APK, key, public release or deployment has been created. Confirm repository visibility and review distribution rights before publishing.

## Release contract
One adaptive ARM APK, application ID `gg.isme.tv.flutter`, Android API 28+, ARM64 and ARMv7. Device detection is unchanged. Debug uses `.debug` and deliberately cannot self-update to a release. x86-only devices are not supported by this release APK.

Publish a stable release tag `vX.Y.Z` with these three assets, generated from the *same* signed APK:
- `isme.apk`
- `update.json` (version, increasing versionCode, packageId, minimumAndroidSdk, abis, asset, bytes, SHA-256)
- `SHA256SUMS.txt`

The updater reads the public GitHub latest stable release, exact repo/tag asset paths, and the manifest. It uses versionCode, checks ABI/minSdk, refuses unexpected hosts or sizes, verifies SHA-256 (and GitHub asset digest if present), validates the APK package, version and matching signing certificate, then opens Android's installer. No GitHub token, backend, silent install, forced update or download during a movie. Android itself checks compatibility/signature again.

Startup checks are delayed slightly. A lightweight foreground timer ticks every minute; network checks are throttled to six hours per running process, failed checks to 15 minutes. Discovery may run during playback, but prompts are deferred during playback and support menus/dialogs. The timer stops when the app leaves the foreground; no persistent service is installed. Manual checks bypass cooldown. Later suppresses that release for six hours (persisted). A pending update prompt waits until the playback screen exits. Background completion is shown on return. The user can cancel the download, retry failure or postpone installation. Temporary files are removed on normal failure/cancel; a stale partial file after abrupt process death is replaced on the next download. Downloading does not persist across process death.

## Signing and release preparation
Before building a real release, establish and securely back up a permanent Android signing keystore. Never send private key or passwords in chat or commit them. If any existing *release* APK is distributed, reuse its signing identity; debug installations have a different package ID and are not upgraded by a release. No production signing key was created or inspected here.

Local Gradle release configuration reads ignored `android/key.properties` (storeFile relative to android/ or absolute path, storePassword, keyAlias, keyPassword) or environment variables ISME_KEYSTORE_PATH, ISME_KEYSTORE_PASSWORD, ISME_KEY_ALIAS, ISME_KEY_PASSWORD. Release tasks fail without signing configuration. Existing debug setup is unchanged.

## GitHub Actions (manual dispatch)
Configure GitHub environments **android-signing** (restrict to main) and **android-public-release** (restrict to main and require reviewer approval where supported). Under android-signing set secrets ISME_KEYSTORE_BASE64, ISME_KEYSTORE_PASSWORD, ISME_KEY_ALIAS, ISME_KEY_PASSWORD; set environment variable ISME_SIGNER_SHA256 to the permanent certificate's public SHA-256 fingerprint. Base64 is an encoding, not encryption; store it only as a protected secret. Keep an offline encrypted backup.

Run Android release candidate from Actions on main with a stable version and unique monotonically increasing versionCode. Default publish=false builds, tests, signs and uploads a private workflow artifact only. Enable publish=true only after signed device testing, and approve the public-release environment; the workflow checks the prior stable release's manifest before publishing and refuses an existing release. If an older release lacks update.json, migrate deliberately rather than bypassing the check. Restrict Actions permissions and review action version pinning before production. The configured Flutter 3.38.0 CI toolchain must be validated; local Windows Gradle versions have previously differed. A private repository cannot serve anonymous in-app checks.

## Verification checklist
1. Run python3 -B -m unittest discover -s tools -p 'test_release_metadata.py'. Tests use fake Android tools, not real APK verification.
2. Windows: flutter analyze, flutter test, run both device shells and check playback; debug updater menu reports disabled.
3. Build two consecutively numbered signed release candidates using the same key. Use an ARM physical phone and Android TV (or compatible emulator). Test the older release against a controlled test release before public rollout.
4. Check startup, foreground, manual, latest/no release/offline, release ignored during playback, duplicate prompt, postpone, download cancellation, low storage, retry, installer permission denied/granted, installer cancel, successful installation and preservation of history/settings. Test D-pad focus and long changelogs.
5. Test wrong checksum, signer, versionCode, package, ABI, size, missing manifest, redirected untrusted host, prerelease, and inaccessible GitHub. Confirm no downgrade or unsigned update installs.
6. Verify APK certificate, ARM native playback libraries, launcher/leanback intents and Android compatibility using actual Android tools and devices. Confirm current stable manifest is accessible anonymously. Review release notes and website download links separately. Publish only after approval.
