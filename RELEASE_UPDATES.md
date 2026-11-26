# isme.gg GitHub Releases updater

## Distribution

The [official website](https://bastilavarias.github.io/isme.gg/#download) reads a public release feed generated from GitHub Releases. The website and the in-app updater use the same signed APK.

## Release contract
One adaptive ARM APK, application ID `gg.isme.tv.flutter`, Android API 28+, ARM64 and ARMv7. Device detection is unchanged. Debug uses `.debug` and deliberately cannot self-update to a release. x86-only devices are not supported by this release APK.

Publish a stable release tag `vX.Y.Z` with these three assets, generated from the *same* signed APK:
- `isme.apk`
- `update.json` (version, increasing versionCode, packageId, minimumAndroidSdk, abis, asset, bytes, SHA-256)
- `SHA256SUMS.txt`

The updater reads `https://github.com/bastilavarias/isme.gg/releases/latest/download/update.json` directly, avoiding the anonymous GitHub REST API rate limit. It derives an exact repo/tag APK path from the validated stable manifest version. It uses versionCode, checks ABI/minSdk, refuses unexpected hosts or sizes, verifies manifest SHA-256 and byte count, validates the APK package, version and matching signing certificate, then opens Android's installer. Manifest discovery retries once on selected transient network errors or HTTP 429/5xx. Logcat tag `IsmeUpdater` records exception details and HTTP status without signed redirect URLs. Optional manifest `notes` replaces REST release-body text; existing manifests without notes retain the generic changelog. Existing installed builds need a one-time manual update if their old REST-based updater fails. No GitHub token, backend, silent install, forced update or download during a movie. Android itself checks compatibility/signature again.

Startup checks are delayed slightly. A lightweight foreground timer ticks every minute; network checks are throttled to six hours per running process, failed checks to 15 minutes. Discovery may run during playback, but prompts are deferred during playback and support menus/dialogs. The timer stops when the app leaves the foreground; no persistent service is installed. Manual checks bypass cooldown. Later suppresses that release for six hours (persisted). A pending update prompt waits until the playback screen exits. Background completion is shown on return. The user can cancel the download, retry failure or postpone installation. Temporary files are removed on normal failure/cancel; a stale partial file after abrupt process death is replaced on the next download. Downloading does not persist across process death.

## Signing and release preparation
Use the existing permanent Android signing keystore and keep its encrypted backup. Keep private keys and passwords out of Git and chat. Debug installations use a separate package ID.

Local Gradle release configuration reads ignored `android/key.properties` (storeFile relative to android/ or absolute path, storePassword, keyAlias, keyPassword) or environment variables ISME_KEYSTORE_PATH, ISME_KEYSTORE_PASSWORD, ISME_KEY_ALIAS, ISME_KEY_PASSWORD. Release tasks fail without signing configuration. Existing debug setup is unchanged.

## GitHub Actions (manual dispatch)
The **android-signing** and **android-public-release** environments are restricted to main. The signing environment uses the protected secrets ISME_KEYSTORE_BASE64, ISME_KEYSTORE_PASSWORD, ISME_KEY_ALIAS and ISME_KEY_PASSWORD, plus the public certificate fingerprint in ISME_SIGNER_SHA256. Publication also requires TMDB_API_KEY or TMDB_READ_TOKEN provisioned for distribution inside the public client. APK recipients can extract that credential.

Run **Android release candidate** from Actions on main with a stable version and an increasing versionCode. Match both values to `pubspec.yaml` for the release commit. The default `publish=false` tests, signs and uploads a workflow artifact. After validating the signed candidate on compatible devices, run the workflow with `publish=true` on the same commit and have a designated reviewer approve the public release environment. The workflow uses the pins in [toolchain.json](toolchain.json), checks prior release metadata and rejects an existing release tag. GitHub Pages refreshes the download feed when the publish workflow succeeds.

## Verification checklist
1. Run python3 -B -m unittest discover -s tools -p 'test_release_metadata.py'. Tests use fake Android tools, not real APK verification.
2. Windows: flutter analyze, flutter test, run both device shells and check playback; debug updater menu reports disabled.
3. Build two consecutively numbered signed release candidates using the same key. Use an ARM physical phone and Android TV (or compatible emulator). Test the older release against a controlled test release before public rollout.
4. Check startup, foreground, manual, latest/no release/offline, release ignored during playback, duplicate prompt, postpone, download cancellation, low storage, retry, installer permission denied/granted, installer cancel, successful installation and preservation of history/settings. Test D-pad focus and long changelogs.
5. Test wrong checksum, signer, versionCode, package, ABI, size, missing manifest, redirected untrusted host, prerelease, and inaccessible GitHub. Confirm no downgrade or unsigned update installs.
6. Verify APK certificate, ARM native playback libraries, launcher/leanback intents and Android compatibility using actual Android tools and devices. Confirm current stable manifest is accessible anonymously. Review release notes and website download links separately. Publish only after approval.
