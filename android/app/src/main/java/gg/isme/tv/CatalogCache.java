package gg.isme.tv;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import org.json.JSONObject;

/** Small, disposable metadata cache. Never stores playback bytes or credentials. */
final class CatalogCache extends SQLiteOpenHelper {
    static final long HOUR = 3600000L;
    static final long DAY = 24 * HOUR;
    private static final int MAX_CATALOG_BYTES = 256 * 1024;
    private static final int MAX_PROVIDER_BYTES = 4096;

    CatalogCache(Context context) { super(context, "isme-metadata-v1.db", null, 1); }

    @Override public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE entries (kind TEXT NOT NULL, cache_key TEXT NOT NULL, payload TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY(kind,cache_key))");
        db.execSQL("CREATE INDEX entries_age ON entries(kind,updated)");
    }

    @Override public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        db.execSQL("DROP TABLE IF EXISTS entries");
        onCreate(db);
    }

    static final class Entry {
        final JSONObject data;
        final long updated;
        Entry(JSONObject data, long updated) { this.data = data; this.updated = updated; }
        boolean fresh(long ttl) {
            long age = System.currentTimeMillis() - updated;
            return age >= 0 && age < ttl;
        }
    }

    synchronized Entry read(String kind, String key) {
        try (Cursor c = getReadableDatabase().query("entries", new String[]{"payload","updated"},
                "kind=? AND cache_key=?", new String[]{kind,key}, null,null,null)) {
            if (c.moveToFirst()) return new Entry(new JSONObject(c.getString(0)), c.getLong(1));
        } catch (Exception ignored) {
            // A corrupt or unavailable cache must not block live browsing.
        }
        return null;
    }

    synchronized void write(String kind, String key, JSONObject data) {
        try {
            boolean catalog = "catalog".equals(kind) || "tv_catalog".equals(kind) || "episodes".equals(kind) || "platform_catalog".equals(kind) || "platform_directory".equals(kind);
            String payload = data.toString();
            if (payload.getBytes(java.nio.charset.StandardCharsets.UTF_8).length >
                    (catalog ? MAX_CATALOG_BYTES : MAX_PROVIDER_BYTES)) return;
            SQLiteDatabase db = getWritableDatabase();
            db.beginTransaction();
            try {
                ContentValues row = new ContentValues();
                row.put("kind",kind); row.put("cache_key",key);
                row.put("payload",payload); row.put("updated",System.currentTimeMillis());
                db.insertWithOnConflict("entries",null,row,SQLiteDatabase.CONFLICT_REPLACE);
                db.execSQL("DELETE FROM entries WHERE kind=? AND updated<?",
                    new Object[]{kind,System.currentTimeMillis()-(catalog?30*DAY:7*DAY)});
                db.execSQL("DELETE FROM entries WHERE kind=? AND cache_key NOT IN "
                    +"(SELECT cache_key FROM entries WHERE kind=? ORDER BY updated DESC,cache_key LIMIT ?)",
                    new Object[]{kind,kind,"episodes".equals(kind)||"platform_catalog".equals(kind)?24:"platform_directory".equals(kind)?4:catalog?12:300});
                db.setTransactionSuccessful();
            } finally { db.endTransaction(); }
        } catch (Exception ignored) {
            // Cache writes are best effort; a full disk must not break playback.
        }
    }

    JSONObject catalog(Context context, String collection, String query, String mode) throws Exception {
        // Do not persist personal search terms; the six home collections are bounded.
        if (!query.trim().isEmpty()) return MediaCatalog.catalog(context,collection,query);
        if (!collection.matches("trending|pinoy|korean|english|action|horror|scifi|top_rated"))
            throw new IllegalArgumentException("Unknown collection");
        long ttl = "trending".equals(collection)?3*HOUR:DAY;
        Entry cached = read("catalog",collection);
        boolean usable = cached != null && cached.fresh(30*DAY);
        if ("cached".equals(mode)) {
            JSONObject data = usable ? cached.data : new JSONObject().put("items",new org.json.JSONArray());
            return data.put("cacheHit",usable).put("stale",!usable || !cached.fresh(ttl));
        }
        if (usable && cached.fresh(ttl) && !"refresh".equals(mode))
            return cached.data.put("cacheHit",true).put("stale",false);
        try {
            JSONObject live = MediaCatalog.catalog(context,collection,query);
            org.json.JSONArray items = live.optJSONArray("items");
            if (items == null || items.length() == 0) {
                if (usable) return cached.data.put("cacheHit",true).put("stale",true);
                return live.put("cacheHit",false).put("stale",false);
            }
            write("catalog",collection,live);
            return live.put("cacheHit",false).put("stale",false);
        } catch (Exception error) {
            if (usable) return cached.data.put("cacheHit",true).put("stale",true);
            throw error;
        }
    }
}
