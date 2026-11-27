package gg.isme.tv;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.ParcelFileDescriptor;
import android.os.ProxyFileDescriptorCallback;
import android.os.storage.StorageManager;
import android.system.ErrnoException;
import android.system.OsConstants;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Experimental in-process ContentDataSource transport. Android's seekable
 * proxy descriptor forwards reads to the verified native cache, not HTTP.
 * No file URI, external grant, or access from another application.
 */
public final class DirectMediaProvider extends ContentProvider {
    private static final Object LOCK = new Object();
    private static final Semaphore DESCRIPTORS = new Semaphore(8);
    private static TorrentEngine engine;
    private static String instance;

    static void bind(TorrentEngine source) {
        if (!BuildConfig.DEBUG) return;
        synchronized (LOCK) {
            engine = source;
            instance = UUID.randomUUID().toString();
        }
    }

    static void unbind(TorrentEngine source) {
        synchronized (LOCK) {
            if (engine == source) { engine = null; instance = null; }
        }
    }

    static Uri uri(Context context, TorrentEngine source, long generation) {
        synchronized (LOCK) {
            if (!BuildConfig.DEBUG || engine != source || instance == null) return null;
            return new Uri.Builder().scheme("content")
                .authority(context.getPackageName() + ".directmedia")
                .appendPath(instance).appendPath(Long.toString(generation)).build();
        }
    }

    static void cancel(Uri uri) {
        if (!BuildConfig.DEBUG || uri == null) return;
        List<String> parts = uri.getPathSegments();
        synchronized (LOCK) {
            if (engine == null || parts.size() != 2 || !parts.get(0).equals(instance)) return;
            try { engine.cancelDirectReaders(Long.parseLong(parts.get(1))); }
            catch (NumberFormatException ignored) {}
        }
    }

    private TorrentEngine.DirectReader reader(Uri uri, String mode) throws FileNotFoundException {
        List<String> parts = uri.getPathSegments();
        if (!BuildConfig.DEBUG || !"r".equals(mode) || parts.size() != 2 ||
                android.os.Binder.getCallingUid() != android.os.Process.myUid())
            throw new FileNotFoundException("Direct media unavailable");
        synchronized (LOCK) {
            if (engine == null || !parts.get(0).equals(instance))
                throw new FileNotFoundException("Playback changed");
            try { return engine.openDirectReader(Long.parseLong(parts.get(1))); }
            catch (IOException | NumberFormatException e) {
                throw new FileNotFoundException("Playback unavailable");
            }
        }
    }

    @Override public boolean onCreate() { return true; }

    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!DESCRIPTORS.tryAcquire()) throw new FileNotFoundException("Too many media readers");
        TorrentEngine.DirectReader source;
        try { source = reader(uri, mode); }
        catch (FileNotFoundException | RuntimeException e) {
            DESCRIPTORS.release();
            throw e;
        }
        HandlerThread worker = new HandlerThread("isme-direct-reader");
        AtomicBoolean released = new AtomicBoolean();
        Runnable cleanup = () -> {
            if (released.compareAndSet(false, true)) {
                try { source.close(); } catch (IOException ignored) {}
                worker.quitSafely();
                DESCRIPTORS.release();
            }
        };
        try {
            worker.start();
            StorageManager storage = getContext().getSystemService(StorageManager.class);
            if (storage == null) throw new IOException("Storage service unavailable");
            return storage.openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_ONLY,
                new ProxyFileDescriptorCallback() {
                    @Override public long onGetSize() { return source.size(); }
                    @Override public int onRead(long offset, int size, byte[] data) throws ErrnoException {
                        long start = android.os.SystemClock.elapsedRealtime();
                        try {
                            int read = source.read(offset, size, data);
                            long ms = android.os.SystemClock.elapsedRealtime() - start;
                            if (ms >= 1000)
                                android.util.Log.d("IsmeDirect", "read offset=" + offset + " bytes=" + read + " waitMs=" + ms);
                            return read;
                        } catch (Exception e) {
                            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
                            String reason = "Media data deadline exceeded".equals(e.getMessage())
                                ? "piece-timeout" : "read-failed";
                            android.util.Log.w("IsmeDirect", reason + " offset=" + offset
                                + " bytes=" + size + " waitMs=" + (android.os.SystemClock.elapsedRealtime() - start));
                            throw new ErrnoException("direct read", OsConstants.EIO);
                        }
                    }
                    @Override public void onRelease() { cleanup.run(); }
                }, new Handler(worker.getLooper()));
        } catch (Exception e) {
            cleanup.run();
            android.util.Log.w("IsmeDirect", "descriptor-open-failed type=" + e.getClass().getSimpleName());
            throw new FileNotFoundException("Direct descriptor unavailable");
        }
    }

    @Override public AssetFileDescriptor openAssetFile(Uri uri, String mode) throws FileNotFoundException {
        // Media3's ContentDataSource uses this API. The proxy supports seek
        // and reports the selected length through fstat/onGetSize.
        ParcelFileDescriptor descriptor = openFile(uri, mode);
        long size = descriptor.getStatSize();
        return new AssetFileDescriptor(descriptor, 0, size >= 0 ? size : AssetFileDescriptor.UNKNOWN_LENGTH);
    }
    @Override public String getType(Uri uri) { return "application/octet-stream"; }
    @Override public Cursor query(Uri uri, String[] p, String s, String[] a, String order) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String s, String[] a) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
}
