package gg.isme.tv;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class ReleaseUpdater {
    interface Listener { void available(Release release); }
    interface DownloadListener { void ready(); void error(String message); }

    static final class Release {
        final String version;
        final URL url;
        final long size;
        final String sha256;

        Release(String version, URL url, long size, String sha256) {
            this.version = version;
            this.url = url;
            this.size = size;
            this.sha256 = sha256;
        }
    }

    private static final long MAX_APK_SIZE = 200L * 1024 * 1024;
    private final Activity activity;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private File verifiedApk;
    private boolean awaitingInstallPermission;

    ReleaseUpdater(Activity activity) { this.activity = activity; }

    void check(Listener listener) {
        String repo = BuildConfig.RELEASE_REPO.trim();
        if (!repo.matches("[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+")) return;
        worker.execute(() -> {
            try {
                URL url = new URL("https://api.github.com/repos/" + repo + "/releases/latest");
                HttpURLConnection connection = (HttpURLConnection) url.openConnection();
                connection.setConnectTimeout(10000);
                connection.setReadTimeout(12000);
                connection.setRequestProperty("Accept", "application/vnd.github+json");
                connection.setRequestProperty("User-Agent", "isme-tv-updater");
                JSONObject data;
                try {
                    if (connection.getResponseCode() != 200) return;
                    byte[] bytes = readLimited(connection.getInputStream(), 1024 * 1024);
                    data = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
                } finally {
                    connection.disconnect();
                }
                if (data.optBoolean("draft") || data.optBoolean("prerelease")) return;
                String version = data.optString("tag_name").replaceFirst("^tv-v", "");
                if (!isNewer(version, BuildConfig.VERSION_NAME)) return;
                JSONArray assets = data.optJSONArray("assets");
                if (assets == null) return;
                for (int i = 0; i < assets.length(); i++) {
                    JSONObject asset = assets.optJSONObject(i);
                    if (asset == null || !"isme-tv.apk".equals(asset.optString("name"))) continue;
                    String digest = asset.optString("digest");
                    long size = asset.optLong("size");
                    URL download = new URL(asset.optString("browser_download_url"));
                    if (!"https".equals(download.getProtocol()) || !"github.com".equals(download.getHost())
                            || size <= 0 || size > MAX_APK_SIZE
                            || !digest.matches("sha256:[a-fA-F0-9]{64}")) return;
                    Release release = new Release(version, download, size, digest.substring(7).toLowerCase());
                    activity.runOnUiThread(() -> listener.available(release));
                    return;
                }
            } catch (Exception error) {
                android.util.Log.w("IsmeUpdater", "Could not check for updates: " + error.getClass().getSimpleName());
            }
        });
    }

    void download(Release release, DownloadListener listener) {
        worker.execute(() -> {
            File temp = null;
            try {
                File directory = new File(activity.getCacheDir(), "updates");
                if (!directory.exists() && !directory.mkdirs()) throw new Exception("Cannot create update cache");
                temp = new File(directory, "isme-tv-download.apk");
                File finished = new File(directory, "isme-tv.apk");
                HttpURLConnection connection = (HttpURLConnection) release.url.openConnection();
                connection.setInstanceFollowRedirects(true);
                connection.setConnectTimeout(15000);
                connection.setReadTimeout(30000);
                connection.setRequestProperty("User-Agent", "isme-tv-updater");
                MessageDigest hash = MessageDigest.getInstance("SHA-256");
                long total = 0;
                try {
                    if (connection.getResponseCode() != 200) throw new Exception("GitHub download failed");
                    try (InputStream in = connection.getInputStream(); FileOutputStream out = new FileOutputStream(temp)) {
                        byte[] buffer = new byte[16384];
                        int n;
                        while ((n = in.read(buffer)) != -1) {
                            total += n;
                            if (total > MAX_APK_SIZE) throw new Exception("APK is too large");
                            hash.update(buffer, 0, n);
                            out.write(buffer, 0, n);
                        }
                    }
                } finally {
                    connection.disconnect();
                }
                if (total != release.size || !hex(hash.digest()).equals(release.sha256))
                    throw new Exception("APK checksum mismatch");
                verifyArchive(temp);
                if (finished.exists() && !finished.delete()) throw new Exception("Cannot replace old APK");
                if (!temp.renameTo(finished)) throw new Exception("Cannot save verified APK");
                verifiedApk = finished;
                activity.runOnUiThread(listener::ready);
            } catch (Exception error) {
                if (temp != null) temp.delete();
                activity.runOnUiThread(() -> listener.error("Update failed: " + error.getMessage()));
            }
        });
    }

    private void verifyArchive(File apk) throws Exception {
        PackageManager pm = activity.getPackageManager();
        PackageInfo installed = pm.getPackageInfo(activity.getPackageName(), PackageManager.GET_SIGNING_CERTIFICATES);
        PackageInfo incoming = pm.getPackageArchiveInfo(apk.getAbsolutePath(), PackageManager.GET_SIGNING_CERTIFICATES);
        if (incoming == null || !activity.getPackageName().equals(incoming.packageName)
                || installed.signingInfo == null || incoming.signingInfo == null)
            throw new Exception("APK package or signature missing");
        Signature[] existing = installed.signingInfo.getApkContentsSigners();
        Signature[] offered = incoming.signingInfo.getApkContentsSigners();
        if (existing.length != offered.length || !Arrays.equals(existing, offered))
            throw new Exception("APK signer does not match installed app");
        if (Build.VERSION.SDK_INT >= 28 && incoming.getLongVersionCode() <= installed.getLongVersionCode())
            throw new Exception("APK version code is not newer");
    }

    void install() {
        File file = verifiedApk;
        if (file == null || !file.isFile()) {
            Toast.makeText(activity, "No verified update ready", Toast.LENGTH_LONG).show();
            return;
        }
        if (Build.VERSION.SDK_INT >= 26 && !activity.getPackageManager().canRequestPackageInstalls()) {
            awaitingInstallPermission = true;
            Toast.makeText(activity, "Allow updates from isme.gg, then return", Toast.LENGTH_LONG).show();
            Intent permission = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + activity.getPackageName()));
            activity.startActivity(permission);
            return;
        }
        awaitingInstallPermission = false;
        Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", file);
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activity.startActivity(intent);
    }

    void resumePendingInstall() {
        if (awaitingInstallPermission && activity.getPackageManager().canRequestPackageInstalls()) install();
    }

    void close() { worker.shutdownNow(); }

    private static byte[] readLimited(InputStream in, int limit) throws Exception {
        try (InputStream input = in; java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int n;
            while ((n = input.read(buffer)) != -1) {
                if (out.size() + n > limit) throw new Exception("Release metadata too large");
                out.write(buffer, 0, n);
            }
            return out.toByteArray();
        }
    }

    private static String hex(byte[] bytes) {
        StringBuilder value = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) value.append(String.format(java.util.Locale.ROOT, "%02x", b & 0xff));
        return value.toString();
    }

    private static boolean isNewer(String candidate, String current) {
        String[] first = candidate.split("\\.");
        String[] second = current.split("\\.");
        if (first.length != 3 || second.length != 3) return false;
        try {
            for (int i = 0; i < 3; i++) {
                if (!first[i].matches("[0-9]+") || !second[i].matches("[0-9]+")) return false;
                int a = Integer.parseInt(first[i]), b = Integer.parseInt(second[i]);
                if (a != b) return a > b;
            }
        } catch (NumberFormatException ignored) {}
        return false;
    }
}
