package gg.isme.tv;

import android.content.ContentValues;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import org.json.JSONArray;
import org.json.JSONObject;

/** Durable user data in the existing SQLite database, outside cache eviction. */
final class UserLibrary {
    private final CatalogCache helper;
    UserLibrary(CatalogCache helper) { this.helper = helper; }

    static void createTables(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE IF NOT EXISTS bookmarks (media_id TEXT PRIMARY KEY NOT NULL, media_kind TEXT NOT NULL, tmdb_id INTEGER NOT NULL DEFAULT 0, added_at INTEGER NOT NULL, payload TEXT NOT NULL)");
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS bookmarks_tmdb ON bookmarks(media_kind,tmdb_id) WHERE tmdb_id>0");
        db.execSQL("CREATE INDEX IF NOT EXISTS bookmarks_added ON bookmarks(added_at DESC)");
        db.execSQL("CREATE TABLE IF NOT EXISTS watch_history (media_id TEXT PRIMARY KEY NOT NULL, position_seconds INTEGER NOT NULL, duration_seconds INTEGER NOT NULL, updated_at INTEGER NOT NULL, payload TEXT NOT NULL)");
        db.execSQL("CREATE INDEX IF NOT EXISTS watch_history_updated ON watch_history(updated_at DESC)");
        db.execSQL("CREATE TABLE IF NOT EXISTS library_migrations (name TEXT PRIMARY KEY NOT NULL)");
    }

    private static boolean valid(JSONObject row) {
        return !row.optString("id").isEmpty() && !row.optString("title").isEmpty();
    }

    private static void bookmark(SQLiteDatabase db, JSONObject row, int conflict) {
        if (!valid(row)) throw new IllegalArgumentException("Invalid bookmark");
        String id = row.optString("id");
        if (!id.matches("imdb:tt[0-9]{7,10}|tmdb:(movie|tv):[1-9][0-9]{0,8}"))
            throw new IllegalArgumentException("Invalid bookmark ID");
        String type = row.optString("type");
        String kind = "Series".equals(type) || "Anime".equals(type) ? "tv" : "movie";
        int tmdb = row.optInt("tmdbId", 0);
        if (tmdb <= 0 && id.startsWith("tmdb:")) tmdb = Integer.parseInt(id.substring(id.lastIndexOf(':') + 1));
        ContentValues values = new ContentValues();
        values.put("media_id", id);
        values.put("media_kind", kind);
        values.put("tmdb_id", Math.max(0, tmdb));
        values.put("added_at", Math.max(0L, row.optLong("addedAt", 0)));
        values.put("payload", row.toString());
        long result = db.insertWithOnConflict("bookmarks", null, values, conflict);
        if (result == -1 && conflict != SQLiteDatabase.CONFLICT_IGNORE)
            throw new IllegalStateException("Bookmark write failed");
    }

    private static void history(SQLiteDatabase db, JSONObject row, int conflict) {
        if (!valid(row) || row.optLong("time", -1) < 0 || row.optLong("duration", -1) < 0)
            throw new IllegalArgumentException("Invalid watch progress");
        ContentValues values = new ContentValues();
        values.put("media_id", row.optString("id"));
        values.put("position_seconds", row.optLong("time"));
        values.put("duration_seconds", row.optLong("duration"));
        values.put("updated_at", Math.max(0L, row.optLong("updated", 0)));
        values.put("payload", row.toString());
        long result = db.insertWithOnConflict("watch_history", null, values, conflict);
        if (result == -1 && conflict != SQLiteDatabase.CONFLICT_IGNORE)
            throw new IllegalStateException("History write failed");
    }

    private static void trimHistory(SQLiteDatabase db) {
        db.execSQL("DELETE FROM watch_history WHERE media_id NOT IN (SELECT media_id FROM watch_history ORDER BY updated_at DESC, rowid DESC LIMIT 30)");
    }

    String open(String oldBookmarks, String oldHistory) throws Exception {
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransaction();
        try {
            boolean migrated;
            try (Cursor cursor = db.rawQuery("SELECT 1 FROM library_migrations WHERE name=?", new String[]{"prefs-library-v1"})) {
                migrated = cursor.moveToFirst();
            }
            if (!migrated) {
                JSONArray bookmarks = new JSONArray(oldBookmarks);
                JSONObject watch = new JSONObject(oldHistory);
                for (int i = 0; i < bookmarks.length(); i++) {
                    JSONObject row = bookmarks.optJSONObject(i);
                    if (row != null) bookmark(db, row, SQLiteDatabase.CONFLICT_IGNORE);
                }
                java.util.Iterator<String> ids = watch.keys();
                while (ids.hasNext()) {
                    JSONObject row = watch.optJSONObject(ids.next());
                    if (row != null) history(db, row, SQLiteDatabase.CONFLICT_IGNORE);
                }
                trimHistory(db);
                db.execSQL("INSERT INTO library_migrations(name) VALUES (?)", new Object[]{"prefs-library-v1"});
            }
            String snapshot = new JSONObject()
                .put("bookmarks", rows(db, "bookmarks", "added_at DESC, rowid ASC"))
                .put("history", rows(db, "watch_history", "updated_at DESC, rowid DESC")).toString();
            db.setTransactionSuccessful();
            return snapshot;
        } finally { db.endTransaction(); }
    }

    private static JSONArray rows(SQLiteDatabase db, String table, String order) throws Exception {
        JSONArray result = new JSONArray();
        try (Cursor cursor = db.query(table, new String[]{"payload"}, null, null, null, null, order)) {
            while (cursor.moveToNext()) result.put(new JSONObject(cursor.getString(0)));
        }
        return result;
    }

    String readBookmarks() throws Exception {
        return rows(helper.getReadableDatabase(), "bookmarks", "added_at DESC, rowid ASC").toString();
    }

    void saveBookmark(String id, String payload) throws Exception {
        SQLiteDatabase db = helper.getWritableDatabase();
        if (payload == null) db.delete("bookmarks", "media_id=?", new String[]{id});
        else {
            JSONObject row = new JSONObject(payload);
            if (!id.equals(row.optString("id"))) throw new IllegalArgumentException("Bookmark ID mismatch");
            bookmark(db, row, SQLiteDatabase.CONFLICT_ABORT);
        }
    }

    void saveHistory(String id, String payload) throws Exception {
        SQLiteDatabase db = helper.getWritableDatabase();
        db.beginTransaction();
        try {
            if (payload == null) db.delete("watch_history", "media_id=?", new String[]{id});
            else {
                JSONObject row = new JSONObject(payload);
                if (!id.equals(row.optString("id"))) throw new IllegalArgumentException("History ID mismatch");
                history(db, row, SQLiteDatabase.CONFLICT_REPLACE);
                trimHistory(db);
            }
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
    }
}
