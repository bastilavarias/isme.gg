# Local metadata cache and regional availability pills

## Scope
Android's built-in SQLiteOpenHelper creates isme-metadata-v1.db in app-private storage. No Flutter database plugin, server database, authentication secret in the APK, or additional video storage. Existing SharedPreferences history/preferences and playback piece cache are unchanged. Artwork still uses Flutter's existing memory cache, not a new disk cache.

- Home collections: 3 hours for trending, 24 hours for others; stale snapshots can be displayed for up to 30 days if refresh fails. Bundled language catalogs refresh from packaged assets. First launch fetches uncached data normally.
- Catalog payload: maximum 256 KiB per entry, 12 entries. Provider payload: 4 KiB per entry, 300 entries. Old records are pruned on write (30 days for catalogs, 7 days for providers). These are logical payload/record limits, not an exact SQLite file-size ceiling.
- Search terms are not stored. Live search falls back to the already loaded local shelves on failure.
- Active focused rails are not replaced during a refresh; the new snapshot is saved for a later reload. Cache failure is nonfatal.
- Provider data uses official TMDB Find and Movie Watch Providers, with JustWatch attribution. Country defaults to PH, is editable and persisted. One distinct subscription provider with no other free/ad-supported platform gets a small text pill; rentals/purchases do not count. This is a regional availability indicator, not proof of exclusivity or origin.
- Configure Menu > Streaming availability with a TMDB API Read Access Token. Token is held only in memory for the app session and sent to the authenticated loopback engine and TMDB over HTTPS. It is not written to SQLite, preferences or Git. No token: use fresh saved provider entries, otherwise no badge. Provider records expire for display after 24 hours; unavailable/ambiguous results are cached too. Failed requests do not overwrite successful entries. Two asynchronous request lanes and in-memory deduplication keep lookups out of the UI path. Auth/rate-limit failures stop further remote provider requests for the session until configuration changes.
- Before distribution confirm TMDB/JustWatch licensing and required logo/attribution arrangements. No public production credential is provisioned.

## Windows/device validation
1. Run setupwindows.bat after pulling the committed changes; a full Android rebuild is required for new Java classes.
2. Browse home online, close and reopen; shelves should appear before remote refresh. Disable internet and reopen: saved metadata remains available, missing artwork may need network, live playback is not guaranteed. Restore network and use Refresh catalog.
3. Use the Android debug app's private database inspector to verify entries, timestamps and eviction limits; no video bytes, search terms or token should be present.
4. Enter a valid read token and region in Streaming availability; compare a single-provider, multi-provider and unavailable title with official regional availability. Verify the tiny pill stays in the upper-left for portrait and expanded cards, and focus/scroll remain unchanged.
5. Switch countries, clear token, restart offline, test bad/expired token and network error. Never display a badge for ambiguous data or an expired cache. Confirm previously cached fresh entries remain usable without the token.
6. Run flutter analyze and flutter test (including catalog_cache_test.dart). The server has no Flutter/Dart/JDK tools; these checks require the Windows development environment.
