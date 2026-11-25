package gg.isme.tv;

import org.json.JSONArray;
import org.json.JSONObject;
import org.libtorrent4j.FileStorage;
import org.libtorrent4j.Priority;
import org.libtorrent4j.SessionManager;
import org.libtorrent4j.Sha1Hash;
import org.libtorrent4j.TorrentHandle;
import org.libtorrent4j.TorrentInfo;
import org.libtorrent4j.TorrentStatus;
import org.libtorrent4j.swig.torrent_flags_t;

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Android-only torrent engine. Uses libtorrent's native TCP/uTP/UDP/DHT/swarm
 * transport and stores disposable pieces ONLY in this TV's app-private cache.
 * No remote server mediates or stores the video.
 */
final class TorrentEngine {
    private final File root;
    private File activePath;
    private SessionManager session;
    private TorrentHandle handle;
    private File movieFile;
    private FileStorage storage;
    private int selectedIndex = -1;
    private int pieceLength;
    private long fileOffset;
    private long movieLength;
    private String currentId = "";
    private String title = "";
    private String imdbId = "";
    private String status = "idle";
    private String message = "";
    private String error = "";
    private int selectedSource = 0;
    private List<MediaCatalog.Source> choices = new ArrayList<>();
    // One in-memory candidate snapshot; never persisted to disk.
    private String choiceId = "";
    private List<MediaCatalog.Source> choiceSnapshot = new ArrayList<>();
    private long sequence = 0L;
    private final Object lock = new Object();

    TorrentEngine(File privateCache) {
        root = new File(privateCache, "torrent-pieces");
        // Clear abandoned pieces from a process crash before beginning playback.
        removeRecursively(root);
    }

    void start(String id, String name, int sourceIndex, String directMagnet) {
        final long token;
        final List<MediaCatalog.Source> prior;
        synchronized (lock) {
            // Reuse the exact candidate snapshot for retries of the same title.
            prior = id.equals(choiceId) && (directMagnet == null || directMagnet.isEmpty())
                ? new ArrayList<>(choiceSnapshot) : new ArrayList<>();
            if (!id.equals(choiceId) || (directMagnet != null && !directMagnet.isEmpty())) {
                choiceId = ""; choiceSnapshot.clear();
            }
            stopLocked();
            token = ++sequence;
            currentId = id;
            title = name;
            selectedSource = sourceIndex;
            status = "resolving";
            error = "";
            message = "Finding a compatible torrent source...";
        }
        new Thread(() -> {
            try {
                List<MediaCatalog.Source> found;
                String resolvedImdb = "";
                if (directMagnet != null && !directMagnet.isEmpty()) {
                    java.util.regex.Matcher match = java.util.regex.Pattern
                        .compile("(?i)^magnet:\\?xt=urn:btih:([a-f0-9]{40})(?:&.*)?$")
                        .matcher(directMagnet);
                    if (!match.matches()) throw new IOException("Invalid magnet URI");
                    found = new ArrayList<>();
                    found.add(new MediaCatalog.Source(name, directMagnet, match.group(1),
                        "Unknown", 0, -1, 0));
                } else {
                    String imdb = id.startsWith("imdb:") ? id.substring(5) : "";
                    if (!imdb.matches("tt[0-9]{7,10}"))
                        throw new IOException("This title has no IMDb ID");
                    resolvedImdb = imdb;
                    found = prior.isEmpty() ? MediaCatalog.resolve(imdb, name) : prior;
                }
                if (found.isEmpty()) throw new IOException("No matching torrent sources found");
                if (sourceIndex < 0 || sourceIndex >= found.size()) throw new IOException("Source index unavailable");
                int selection = sourceIndex;
                MediaCatalog.Source chosen = found.get(selection);
                synchronized (lock) {
                    if (token != sequence) return;
                    choices = found;
                    if (directMagnet == null || directMagnet.isEmpty()) {
                        choiceId = id; choiceSnapshot = new ArrayList<>(found);
                    }
                    imdbId = resolvedImdb;
                    selectedSource = selection;
                    status = "loading";
                    message = "Connecting to torrent peers...";
                    activePath = new File(root, "session-" + token);
                    if (!activePath.exists() && !activePath.mkdirs()) throw new IOException("Could not create private cache");
                    session = new SessionManager(false);
                    session.start();
                    session.download(chosen.magnet, activePath, new torrent_flags_t());
                }
            } catch (Throwable failure) {
                synchronized (lock) {
                    if (token == sequence) {
                        status = "error";
                        error = failure.getMessage() == null ? failure.getClass().getSimpleName() : failure.getMessage();
                        message = error;
                    }
                }
            }
        }, "isme-torrent-start").start();
    }

    JSONObject state() throws Exception {
        synchronized (lock) {
            if ("loading".equals(status) && session != null && !choices.isEmpty()) {
                MediaCatalog.Source source = choices.get(selectedSource);
                handle = session.find(Sha1Hash.parseHex(source.hash));
                if (handle != null && handle.isValid()) {
                    TorrentInfo ti = handle.torrentFile();
                    if (ti != null && ti.isValid()) {
                        try { prepareVideo(ti); }
                        catch (Exception e) { status = "error"; error = e.getMessage() == null ? "Media validation failed" : e.getMessage(); message = error; }
                    }
                }
            }
            if ("buffering".equals(status) && handle != null && movieFile != null) {
                int first = (int)(fileOffset / pieceLength);
                if (handle.isValid() && handle.havePiece(first) && movieFile.isFile()) {
                    status = "ready";
                    message = "Ready to stream from peers";
                }
            }
            JSONObject data = new JSONObject().put("id", currentId).put("title", title)
                .put("status", status).put("message", message)
                .put("selectedSource", selectedSource);
            JSONArray list = new JSONArray();
            for (MediaCatalog.Source source : choices) list.put(source.publicJson());
            data.put("sources", list);
            if (handle != null && handle.isValid()) {
                try {
                    TorrentStatus st = handle.status();
                    data.put("peers", st.numPeers());
                    data.put("downloadSpeed", st.downloadRate());
                    data.put("progress", Math.round(st.progress() * 100f));
                } catch (Throwable ignored) {}
            }
            if ("ready".equals(status)) {
                data.put("streamUrl", "/stream/video?session=" + sequence);
                data.put("fileName", movieFile.getName());
                data.put("bytes", movieLength);
                if (!imdbId.isEmpty()) data.put("imdbId", imdbId);
            } else data.put("streamUrl", JSONObject.NULL);
            if (!error.isEmpty()) data.put("error", error);
            return data;
        }
    }

    private void prepareVideo(TorrentInfo ti) throws Exception {
        FileStorage files = ti.files();
        if (files == null || files.numFiles() == 0) return;
        long longest = 0L;
        int picked = -1;
        for (int i = 0; i < files.numFiles(); i++) {
            String filename = files.fileName(i).toLowerCase(Locale.ROOT);
            if (!filename.matches(".*\\.(mp4|m4v|webm|mkv|mov)$")) continue;
            if (files.fileSize(i) > longest) {
                longest = files.fileSize(i);
                picked = i;
            }
        }
        if (picked < 0) throw new IOException("No playable video file found");
        if (longest > MediaCatalog.MAX_BYTES || longest <= 0)
            throw new IOException("Video exceeds 3 GiB device cache limit");

        for (int i = 0; i < files.numFiles(); i++)
            handle.filePriority(i, i == picked ? Priority.DEFAULT : Priority.IGNORE);

        File target = new File(activePath, files.filePath(picked)).getCanonicalFile();
        String parent = activePath.getCanonicalPath() + File.separator;
        if (!target.getPath().startsWith(parent)) throw new IOException("Unsafe torrent file path");

        movieFile = target;
        storage = files;
        selectedIndex = picked;
        pieceLength = files.pieceLength();
        fileOffset = files.fileOffset(picked);
        movieLength = files.fileSize(picked);
        handle.setSequentialRange(Math.toIntExact(fileOffset / pieceLength));
        status = "buffering";
        message = "Waiting for verified initial data";
    }

    long generation() { synchronized (lock) { return sequence; } }
    /** Called by localhost HTTP handlers; a stale request cannot read the next session. */
    void writeRange(long start, long end, long expectedGeneration, OutputStream output) throws Exception {
        TorrentHandle torrent;
        File file;
        long offset;
        int length;
        long generation;
        synchronized (lock) {
            if (expectedGeneration != sequence || !"ready".equals(status) || handle == null || movieFile == null)
                throw new IOException("Movie not ready");
            torrent = handle; file = movieFile; offset = fileOffset; length = pieceLength;
            generation = sequence;
            if (start < 0 || end < start || end >= movieLength) throw new IOException("Invalid byte range");
            int first = (int) ((offset + start) / length);
            torrent.setSequentialRange(first);
        }
        int initialPiece = (int) ((offset + start) / length);
        waitForPiece(torrent, initialPiece, generation);
        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            raf.seek(start);
            byte[] buffer = new byte[32768];
            long position = start;
            while (position <= end) {
                synchronized (lock) {
                    if (sequence != generation || torrent != handle) throw new IOException("Playback changed");
                }
                int piece = (int) ((offset + position) / length);
                waitForPiece(torrent, piece, generation);
                int remainingInPiece = (int) (length - ((offset + position) % length));
                int n = (int) Math.min(Math.min(remainingInPiece, buffer.length), end - position + 1);
                int received = raf.read(buffer, 0, n);
                if (received < 1) throw new IOException("Torrent data is missing on disk");
                output.write(buffer, 0, received);
                position += received;
            }
            output.flush();
        }
    }

    private void waitForPiece(TorrentHandle torrent, int piece, long generation) throws Exception {
        long deadline = android.os.SystemClock.elapsedRealtime() + 35000;
        while (true) {
            synchronized (lock) {
                if (generation != sequence || torrent != handle || !torrent.isValid())
                    throw new IOException("Playback stopped");
                if (torrent.havePiece(piece)) return;
            }
            if (android.os.SystemClock.elapsedRealtime() > deadline)
                throw new IOException("Media data deadline exceeded");
            Thread.sleep(125);
        }
    }

    String currentImdbId() { synchronized (lock) { return imdbId; } }
    String currentFileName() { synchronized (lock) { return movieFile == null ? "" : movieFile.getName(); } }
    long movieSize() { synchronized (lock) { return movieLength; } }
    String mimeType() {
        synchronized (lock) {
            String filename = movieFile == null ? "" : movieFile.getName().toLowerCase(Locale.ROOT);
            if (filename.endsWith(".webm")) return "video/webm";
            if (filename.endsWith(".mkv")) return "video/x-matroska";
            return "video/mp4";
        }
    }

    void stop() { synchronized (lock) { stopLocked(); sequence++; } }

    private void stopLocked() {
        SessionManager previous = session;
        File oldPath = activePath;
        activePath = null;
        session = null; handle = null; movieFile = null; storage = null;
        pieceLength = 0; selectedIndex = -1; movieLength = 0; fileOffset = 0;
        choices = new ArrayList<>(); status = "idle"; currentId = ""; title = "";
        message = "Choose a title to begin"; error = ""; imdbId = "";
        // Stop and delete asynchronously, outside the UI/main thread.
        if (previous != null) new Thread(() -> {
            try { previous.stop(); } catch (Throwable e) { android.util.Log.w("IsmeTorrent", "Engine stop failed", e); }
            if (oldPath != null) removeRecursively(oldPath);
        }, "isme-torrent-cleanup").start();
        else if (oldPath != null) removeRecursively(oldPath);
    }

    private static void removeRecursively(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) for (File child : children) removeRecursively(child);
        }
        if (file.exists() && !file.delete()) android.util.Log.w("IsmeTorrent", "Cache removal failed: " + file.getName());
    }
}
