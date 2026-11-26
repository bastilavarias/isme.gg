# App-provided metadata access
No user token setup or Enable full catalog button. Both TV and mobile automatically use a build-provided credential. Existing local encrypted credentials are a legacy fallback for unconfigured developer builds.

## Windows development
Copy android/metadata.properties.example to android/metadata.properties, set TMDB_API_KEY to the existing 32-character v3 key (or TMDB_READ_TOKEN to the v4 read token), then stop and rerun the native Flutter debug build. No hot reload for native configuration changes. Existing local properties and signing setup are unaffected. Environment variables TMDB_READ_TOKEN / TMDB_API_KEY take precedence over the ignored file.

## Production
Set one repository or android-signing environment secret: TMDB_API_KEY (v3) or TMDB_READ_TOKEN (v4). The signed build job reads these secrets. Public publishing is blocked without a configured credential; build-only jobs may still exercise key-free fallbacks. The credential is compiled into the APK, so it can be extracted even though it is not in Git or CI logs. Use a dedicated application credential, respect provider usage terms, and rotate if needed. A metadata proxy would be required for true credential secrecy. No media hosting/proxy or central cache is introduced.

The existing on-device SQLite catalog/provider caches, TTLs and cache bounds remain unchanged. Cached data is loaded before network calls; honest fallback collections remain available when service fails. Cache reduces repeat requests per device, not total first-time requests across all installs. No TMDB configuration UI is exposed on either device.

## QA
Build with v3 key, then v4 token, then without credentials. Confirm weekly rows and platform catalogs, offline/cache behavior, retry without token prompts, and both portrait/landscape and TV navigation. Check no credential appears in repository, logs or app errors. Rebuild signed candidate and verify on physical devices before publish.
