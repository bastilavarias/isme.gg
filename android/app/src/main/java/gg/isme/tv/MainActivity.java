package gg.isme.tv;

import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.os.Bundle;
import android.view.View;
import android.app.AlertDialog;
import android.widget.Toast;
import java.util.HashMap;
import java.util.Map;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private LocalCinemaServer cinema;
    private ReleaseUpdater updater;
    private boolean tv;
    @Override protected void onCreate(Bundle state) {
        tv = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_TYPE_MASK)
            == Configuration.UI_MODE_TYPE_TELEVISION;
        super.onCreate(state);
        if (tv) {
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
        updater = new ReleaseUpdater(this);
    }
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "gg.isme/native")
            .setMethodCallHandler((call, result) -> {
                if ("connect".equals(call.method)) {
                    try {
                        if (cinema == null) cinema = new LocalCinemaServer(this, false);
                        Map<String,Object> info = new HashMap<>();
                        info.put("origin", cinema.url()); info.put("token", cinema.token()); info.put("tv", tv);
                        result.success(info);
                    } catch (Exception e) { result.error("ENGINE", "Could not start local playback engine", null); }
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
                    if (BuildConfig.RELEASE_REPO.isEmpty()) {
                        result.error("NOT_CONFIGURED", "Release repository not configured", null);
                    } else { checkUpdates(); result.success(null); }
                } else { result.notImplemented(); }
            });
    }
    private void checkUpdates() {
        if (updater == null) return;
        updater.check(release -> {
            if (isFinishing() || isDestroyed()) return;
            new AlertDialog.Builder(this).setTitle("isme.gg update available")
                .setMessage("Version " + release.version)
                .setPositiveButton("Download", (d,w) -> updater.download(release, new ReleaseUpdater.DownloadListener() {
                    public void ready() {
                        if (!isFinishing() && !isDestroyed()) new AlertDialog.Builder(MainActivity.this)
                            .setTitle("Install verified update?").setPositiveButton("Install", (a,b) -> updater.install())
                            .setNegativeButton("Later", null).show();
                    }
                    public void error(String message) { Toast.makeText(MainActivity.this, message, Toast.LENGTH_LONG).show(); }
                })).setNegativeButton("Later", null).show();
        });
    }
    @Override protected void onResume() { super.onResume(); if (updater != null) updater.resumePendingInstall(); }
    @Override protected void onDestroy() {
        if (updater != null) updater.close();
        if (cinema != null) cinema.close();
        super.onDestroy();
    }
}
