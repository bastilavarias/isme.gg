package gg.isme.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.view.ContextThemeWrapper;
import android.widget.TextView;
import android.widget.Toast;

/** Single update flow, shared by phone and TV. All state is on the UI thread. */
final class UpdateFlow {
    private static final long CHECK_INTERVAL=6L*60*60*1000;
    private static final long RETRY_INTERVAL=15L*60*1000;
    private final Activity activity;
    private final ReleaseUpdater updater;
    private final Handler handler=new Handler(Looper.getMainLooper());
    // A lightweight foreground timer; network checks remain rate-limited.
    private static final long TICK_INTERVAL=60L*1000;
    private final Runnable scheduled=this::tick;
    private boolean foreground,playing,supportActive,checking,downloading,cancelRequested,ready,installing,closed;
    private long lastCheck=-CHECK_INTERVAL;
    private ReleaseUpdater.Release pending;
    private AlertDialog dialog;
    private ProgressBar progress;
    private TextView status;
    UpdateFlow(Activity activity){this.activity=activity;updater=new ReleaseUpdater(activity);}
    boolean configured(){return updater.configured();}
    private boolean canPrompt(){return foreground&&!playing&&!supportActive&&!closed;}
    private void schedule(long delay){
        handler.removeCallbacks(scheduled);
        if(foreground&&!closed&&configured())handler.postDelayed(scheduled,delay);
    }
    private void tick(){
        if(!foreground||closed)return;
        check(false);
        schedule(TICK_INTERVAL);
    }
    void supportUi(boolean active){
        supportActive=active;
        if(!active)schedule(500);
    }
    void resume(){
        foreground=true;
        if(updater.takePendingInstall()){
            installing=false;
            if(updater.canInstall())showReady();
            else{ready=true;toast("Installation permission was not granted.");}
        }else if(installing){
            // Android's installer may have been cancelled. Never relaunch it automatically.
            installing=false;ready=false;pending=null;updater.discard();
        }
        if(ready&&dialog==null&&canPrompt())showReady();
        schedule(1600);
    }
    void pause(){foreground=false;handler.removeCallbacks(scheduled);}
    void playback(boolean active){
        playing=active;
        if(active&&dialog!=null&&!downloading){dialog.dismiss();dialog=null;}
        if(!active)schedule(500);
    }
    void check(boolean manual){
        if(closed||!foreground)return;
        if(!configured()){if(manual)toast("Updates are disabled in this build.");return;}
        if(manual&&!canPrompt()){toast("Check for updates after playback or closing the menu.");return;}
        if(checking||downloading||installing||dialog!=null){if(manual)toast("An update check or download is already in progress.");return;}
        if(ready){if(canPrompt())showReady();return;}
        if(pending!=null){if(canPrompt())showAvailable();return;}
        long now=SystemClock.elapsedRealtime();
        if(!manual&&now-lastCheck<CHECK_INTERVAL)return;
        checking=true;lastCheck=now;
        if(manual)toast("Checking for updates…");
        updater.check((release,error)->{
            checking=false;
            if(closed)return;
            if(error!=null){
                // Retry on the next foreground opportunity after a shorter cooldown.
                lastCheck=SystemClock.elapsedRealtime()-CHECK_INTERVAL+RETRY_INTERVAL;
                if(manual&&foreground)toast(error);
                return;
            }
            if(release==null){if(manual&&foreground)toast("isme.gg is up to date.");return;}
            long postponed=activity.getPreferences(Activity.MODE_PRIVATE).getLong("update_later_code",0);
            long until=activity.getPreferences(Activity.MODE_PRIVATE).getLong("update_later_until",0);
            if(!manual&&postponed==release.code&&System.currentTimeMillis()<until)return;
            pending=release;
            if(canPrompt())showAvailable();
        });
    }
    private void later(){
        if(pending!=null)activity.getPreferences(Activity.MODE_PRIVATE).edit()
            .putLong("update_later_code",pending.code)
            .putLong("update_later_until",System.currentTimeMillis()+CHECK_INTERVAL).apply();
        lastCheck=SystemClock.elapsedRealtime();
        pending=null;ready=false;updater.discard();
    }
    private AlertDialog.Builder builder(){return new AlertDialog.Builder(activity,R.style.UpdateDialogTheme);}
    private void show(AlertDialog value){
        if(!canPrompt())return;
        dialog=value;
        value.setOnDismissListener(d->{if(dialog==value)dialog=null;});
        value.show();
        if(value.getButton(AlertDialog.BUTTON_POSITIVE)!=null)value.getButton(AlertDialog.BUTTON_POSITIVE).requestFocus();
    }
    private void showAvailable(){
        if(pending==null||!canPrompt()||dialog!=null)return;
        ReleaseUpdater.Release release=pending;
        String notes=release.notes.isEmpty()?"Performance and stability improvements.":release.notes;
        AlertDialog value=builder().setTitle("Update available")
            .setMessage("v"+BuildConfig.VERSION_NAME+"  →  v"+release.version+"\n\nWhat's new\n"+notes+"\n\nDownload size: "+String.format(java.util.Locale.ROOT,"%.1f MB",release.size/1048576.0))
            .setPositiveButton("Update now",(d,w)->{dialog=null;startDownload();})
            .setNegativeButton("Maybe later",(d,w)->later()).create();
        value.setOnCancelListener(d->later());
        show(value);
    }
    private void startDownload(){
        if(pending==null||!canPrompt()||downloading)return;
        downloading=true;cancelRequested=false;
        int pad=(int)(24*activity.getResources().getDisplayMetrics().density);
        ContextThemeWrapper themed=new ContextThemeWrapper(activity,R.style.UpdateDialogTheme);
        LinearLayout layout=new LinearLayout(themed);layout.setOrientation(LinearLayout.VERTICAL);layout.setPadding(pad,pad/2,pad,pad/2);
        status=new TextView(themed);status.setText("0%");status.setTextSize(22);
        progress=new ProgressBar(themed,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(100);progress.setProgress(0);
        layout.addView(status);layout.addView(progress,new LinearLayout.LayoutParams(-1,-2));
        AlertDialog value=builder().setTitle("Downloading update").setView(layout)
            .setNegativeButton("Cancel",null).setCancelable(false).create();
        show(value);
        value.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v->{
            cancelRequested=true;status.setText("Cancelling…");v.setEnabled(false);updater.cancel();
        });
        updater.download(pending,new ReleaseUpdater.DownloadListener(){
            public void progress(long received,long total){
                if(!downloading||cancelRequested)return;
                int percent=(int)(received*100/total);
                progress.setProgress(percent);status.setText(percent==100?"Verifying…":percent+"%");
            }
            public void ready(){
                downloading=false;dismiss();
                if(cancelRequested){later();return;}
                ready=true;if(canPrompt())showReady();
            }
            public void error(String message){
                downloading=false;dismiss();
                if(cancelRequested){later();return;}
                if(canPrompt())showError(message);
            }
        });
    }
    private void showError(String message){
        if(!canPrompt()||dialog!=null)return;
        AlertDialog value=builder().setTitle("Update failed").setMessage(message)
            .setPositiveButton("Retry",(d,w)->{dialog=null;startDownload();})
            .setNegativeButton("Later",(d,w)->later()).create();
        value.setOnCancelListener(d->later());show(value);
    }
    private void showReady(){
        if(!ready||!canPrompt()||dialog!=null)return;
        AlertDialog value=builder().setTitle("Ready to install")
            .setMessage("The update has been verified. Android will ask you to confirm installation. Your settings and watch progress will be kept.")
            .setPositiveButton("Install update",(d,w)->{
                dialog=null;
                try{installing=true;updater.install();}
                catch(Exception error){installing=false;toast("Unable to open Android installer. Try again.");handler.postDelayed(()->showReady(),300);}
            }).setNegativeButton("Later",(d,w)->later()).create();
        value.setOnCancelListener(d->later());show(value);
    }
    private void toast(String message){if(!closed&&foreground)Toast.makeText(activity,message,Toast.LENGTH_LONG).show();}
    private void dismiss(){if(dialog!=null){dialog.dismiss();dialog=null;}}
    void close(){closed=true;handler.removeCallbacksAndMessages(null);dismiss();updater.close();}
}
