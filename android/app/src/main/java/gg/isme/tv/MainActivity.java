package gg.isme.tv;

import android.app.ActivityManager;
import android.content.Intent;
import android.net.Uri;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;
import java.util.HashMap;
import java.util.Map;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private LocalCinemaServer cinema;
    private UpdateFlow updater;
    private boolean tv;
    private static final String SCREEN_TAG = "IsmeScreenAwake";
    private static final int SCREEN_FLAG = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON;
    private static final long SCREEN_LEASE_MS = 45_000L;
    private static final long SCREEN_CHECK_MS = 5_000L;
    private final Handler screenHandler = new Handler(Looper.getMainLooper());
    private long screenLeaseUntil;
    private boolean foreground;
    private final Runnable screenCheck = this::applyPlaybackScreenFlag;

    private boolean applyPlaybackScreenFlag() {
        screenHandler.removeCallbacks(screenCheck);
        final long now = SystemClock.elapsedRealtime();
        final boolean active = foreground && screenLeaseUntil > now;
        final View decor = getWindow().getDecorView();
        final boolean windowOn = (getWindow().getAttributes().flags & SCREEN_FLAG) != 0;
        if (windowOn != active || decor.getKeepScreenOn() != active) {
            decor.setKeepScreenOn(active);
            if (active) getWindow().addFlags(SCREEN_FLAG);
            else getWindow().clearFlags(SCREEN_FLAG);
            Log.i(SCREEN_TAG, "Keep screen awake=" + active + " foreground=" + foreground);
        }
        if (active) screenHandler.postDelayed(screenCheck, Math.min(SCREEN_CHECK_MS, screenLeaseUntil - now));
        final boolean flagApplied = (getWindow().getAttributes().flags & SCREEN_FLAG) != 0;
        // Acknowledge enable only when both protections are set; acknowledge
        // disable only when both have been cleared.
        return active ? flagApplied && decor.getKeepScreenOn() : flagApplied || decor.getKeepScreenOn();
    }

    private boolean setPlaybackScreenOn(boolean active) {
        screenLeaseUntil = active ? SystemClock.elapsedRealtime() + SCREEN_LEASE_MS : 0;
        return applyPlaybackScreenFlag();
    }
    @Override protected void onCreate(Bundle state) {
        tv = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_TYPE_MASK)
            == Configuration.UI_MODE_TYPE_TELEVISION;
        super.onCreate(state);
        if (tv) {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
        updater = new UpdateFlow(this);
    }
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        io.flutter.plugin.common.BinaryMessenger messenger = engine.getDartExecutor().getBinaryMessenger();
        new MethodChannel(messenger, "gg.isme/library",
                io.flutter.plugin.common.StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler((call, result) -> {
                try (CatalogCache database = new CatalogCache(getApplicationContext())) {
                    UserLibrary library = new UserLibrary(database);
                    switch (call.method) {
                        case "open":
                            result.success(library.open(call.argument("bookmarks"), call.argument("history")));
                            break;
                        case "clearCatalogCache":
                            database.getWritableDatabase().delete("entries", null, null);
                            result.success(null);
                            break;
                        case "clearHistory":
                            database.getWritableDatabase().delete("watch_history", null, null);
                            result.success(null);
                            break;
                        case "readBookmarks":
                            result.success(library.readBookmarks());
                            break;
                        case "bookmark":
                            library.saveBookmark(call.argument("id"), call.argument("payload"));
                            result.success(null);
                            break;
                        case "history":
                            library.saveHistory(call.argument("id"), call.argument("payload"));
                            result.success(null);
                            break;
                        default: result.notImplemented();
                    }
                } catch (Exception e) {
                    result.error("LIBRARY", "Could not access local library database", null);
                }
            });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "gg.isme/native")
            .setMethodCallHandler((call, result) -> {
                if ("connect".equals(call.method)) {
                    try {
                        if (cinema == null) cinema = new LocalCinemaServer(this, false);
                        Map<String,Object> info = new HashMap<>();
                        info.put("origin", cinema.url()); info.put("token", cinema.token()); info.put("tv", tv);
                        info.put("versionName", BuildConfig.VERSION_NAME);
                        info.put("versionCode", BuildConfig.VERSION_CODE);
                        android.content.pm.PackageInfo installed = getPackageManager().getPackageInfo(getPackageName(), 0);
                        info.put("isUpgrade", installed.lastUpdateTime > installed.firstInstallTime);
                        result.success(info);
                    } catch (Exception e) { result.error("ENGINE", "Could not start local playback engine", null); }
                } else if ("readMetadataCredential".equals(call.method)) {
                    result.success(MetadataCredential.read(this));
                } else if ("saveMetadataCredential".equals(call.method)) {
                    try{
                        String credential=call.argument("token");
                        MetadataCredential.save(this,credential==null?"":credential);
                        result.success(null);
                    }catch(Exception e){result.error("CREDENTIAL","Could not save metadata credential",null);}
                } else if ("updateDirectBuffer".equals(call.method)) {
                    String uri = call.argument("uri");
                    if (uri != null) DirectMediaProvider.updateBuffer(Uri.parse(uri), Boolean.TRUE.equals(call.argument("urgent")));
                    result.success(null);
                } else if ("finishDirectStartup".equals(call.method)) {
                    String uri = call.argument("uri");
                    if (uri != null) DirectMediaProvider.finishStartup(Uri.parse(uri));
                    result.success(null);
                } else if ("cancelDirectReads".equals(call.method)) {
                    String uri = call.argument("uri");
                    if (uri != null) DirectMediaProvider.cancel(Uri.parse(uri));
                    result.success(null);
                } else if ("audioDiagnostics".equals(call.method)) {
                    android.media.AudioManager audio = (android.media.AudioManager)getSystemService(AUDIO_SERVICE);
                    Map<String,Object> data = new HashMap<>();
                    if (audio != null) {
                        data.put("sampleRate", audio.getProperty(android.media.AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE));
                        data.put("framesPerBuffer", audio.getProperty(android.media.AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER));
                        data.put("musicVolume", audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC));
                    }
                    result.success(data);
                } else if ("checkUpdates".equals(call.method)) {
                    if (updater == null || !updater.configured()) {
                        result.error("NOT_CONFIGURED", "Updates are disabled in this build", null);
                    } else { updater.check(true); result.success(null); }
                } else if ("setSupportUiActive".equals(call.method)) {
                    if (updater != null) updater.supportUi(Boolean.TRUE.equals(call.argument("active")));
                    result.success(null);
                } else if ("openIssueReport".equals(call.method)) {
                    try {
                        startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/bastilavarias/isme.gg/issues/new")));
                        result.success(null);
                    } catch (Exception e) { result.error("BROWSER", "No browser available", null); }
                } else if ("clearLocalData".equals(call.method)) {
                    // Use Android's own application-data reset, so open databases, native
                    // workers and Flutter preference caches cannot race a partial deletion.
                    // Android terminates this app; the user can reopen to a fresh Home.
                    try {
                        ActivityManager manager = (ActivityManager)getSystemService(ACTIVITY_SERVICE);
                        boolean accepted = manager != null && manager.clearApplicationUserData();
                        result.success(accepted);
                    } catch (Exception e) { result.error("RESET", "Could not clear app data", null); }
                } else if ("setPlaybackScreenOn".equals(call.method)) {
                    result.success(setPlaybackScreenOn(Boolean.TRUE.equals(call.argument("active"))));
                } else if ("setPlaybackActive".equals(call.method)) {
                    if (updater != null) updater.playback(Boolean.TRUE.equals(call.argument("active")));
                    result.success(null);
                } else { result.notImplemented(); }
            });
    }
    @Override protected void onResume() { super.onResume(); foreground = true; applyPlaybackScreenFlag(); if (updater != null) updater.resume(); }
    @Override protected void onPause() { foreground = false; applyPlaybackScreenFlag(); if (updater != null) updater.pause(); super.onPause(); }
    @Override protected void onStop() { screenLeaseUntil = 0; applyPlaybackScreenFlag(); super.onStop(); }
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus && foreground && screenLeaseUntil > SystemClock.elapsedRealtime()) applyPlaybackScreenFlag();
    }
    @Override protected void onDestroy() {
        foreground = false;
        screenLeaseUntil = 0;
        applyPlaybackScreenFlag();
        screenHandler.removeCallbacks(screenCheck);
        if (updater != null) updater.close();
        if (cinema != null) cinema.close();
        super.onDestroy();
    }
}
