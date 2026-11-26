package gg.isme.tv;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

final class ReleaseUpdater {
    interface Listener { void complete(Release release, String error); }
    interface DownloadListener { void progress(long received, long total); void ready(); void error(String message); }
    static final class Release {
        final String version, notes, sha256;
        final long code, size;
        final URL url;
        Release(String version,long code,String notes,URL url,long size,String sha256) {
            this.version=version; this.code=code; this.notes=notes; this.url=url; this.size=size; this.sha256=sha256;
        }
    }
    private static final long MAX_APK_SIZE=200L*1024*1024;
    private static final String APK="isme.apk";
    private final Activity activity;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final AtomicBoolean cancelled=new AtomicBoolean();
    private volatile boolean closed;
    private volatile HttpURLConnection activeDownload;
    private File verifiedApk;
    private Release verifiedRelease;
    private boolean awaitingInstallPermission;
    ReleaseUpdater(Activity activity) { this.activity=activity; }
    private void ui(Runnable callback) {
        if(!closed) activity.runOnUiThread(()->{if(!closed&&!activity.isDestroyed()&&!activity.isFinishing())callback.run();});
    }
    boolean configured(){return !BuildConfig.DEBUG&&BuildConfig.RELEASE_REPO.matches("[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+");}
    private static boolean allowed(URL url) {
        if(!"https".equals(url.getProtocol())||url.getUserInfo()!=null||(url.getPort()!=-1&&url.getPort()!=443))return false;
        String host=url.getHost().toLowerCase(Locale.ROOT);
        return "github.com".equals(host)||"release-assets.githubusercontent.com".equals(host)||"objects.githubusercontent.com".equals(host);
    }
    private static final class HttpFailure extends IOException {
        final int status;
        HttpFailure(int status){super("GitHub returned HTTP "+status);this.status=status;}
    }
    private static HttpURLConnection open(URL initial) throws Exception {
        URL url=initial;
        for(int i=0;i<6;i++){
            if(!allowed(url))throw new IOException("Untrusted update URL");
            HttpURLConnection c=(HttpURLConnection)url.openConnection();
            c.setInstanceFollowRedirects(false);c.setConnectTimeout(12000);c.setReadTimeout(30000);
            c.setRequestProperty("User-Agent","ismegg-updater");
            c.setUseCaches(false);
            int status;
            try{status=c.getResponseCode();}catch(Exception e){c.disconnect();throw e;}
            if(status>=300&&status<400){
                String location=c.getHeaderField("Location");c.disconnect();
                if(location==null)throw new IOException("Invalid release redirect");
                url=new URL(url,location);continue;
            }
            if(status!=200){c.disconnect();throw new HttpFailure(status);}
            return c;
        }
        throw new IOException("Too many update redirects");
    }
    private static JSONObject json(URL url,int limit) throws Exception{
        for(int attempt=0;;attempt++){
            HttpURLConnection c=null;
            try{
                c=open(url);
                return new JSONObject(new String(readLimited(c.getInputStream(),limit),StandardCharsets.UTF_8));
            }catch(IOException e){
                boolean retry=e instanceof java.net.SocketTimeoutException||
                    e instanceof java.net.ConnectException||e instanceof java.net.UnknownHostException||
                    (e instanceof HttpFailure&&(((HttpFailure)e).status==429||
                    ((HttpFailure)e).status>=500));
                if(!retry||attempt>=1)throw e;
                android.util.Log.w("IsmeUpdater","Transient manifest fetch failure: "+diagnostic(e)+"; retrying");
            }finally{if(c!=null)c.disconnect();}
            Thread.sleep(1000L);
        }
    }
    private static String diagnostic(Exception e){
        String message=e.getMessage();
        // Never print signed redirect URLs or their query credentials.
        if(message!=null)message=message.replaceAll("https?://\\S+","[URL]");
        if(message!=null&&message.length()>240)message=message.substring(0,240);
        return e.getClass().getSimpleName()+(message==null?"":": "+message);
    }
    void check(Listener listener){
        if(!configured()){ui(()->listener.complete(null,"Updates are disabled in this build."));return;}
        worker.execute(()->{
            try{
                String repo=BuildConfig.RELEASE_REPO;
                // GitHub's latest-download endpoint resolves the stable public release
                // without the anonymous REST API's per-IP quota.
                JSONObject manifest=json(new URL("https://github.com/"+repo+"/releases/latest/download/update.json"),64*1024);
                long code=manifest.getLong("versionCode");
                String version=manifest.getString("version");
                String tag="v"+version;
                if(!tag.matches("v[0-9]+\\.[0-9]+\\.[0-9]+")||code<=0||!APK.equals(manifest.getString("asset"))||!activity.getPackageName().equals(manifest.getString("packageId")))
                    throw new IOException("Release metadata mismatch");
                if(code<=BuildConfig.VERSION_CODE){ui(()->listener.complete(null,null));return;}
                if(manifest.getInt("minimumAndroidSdk")>Build.VERSION.SDK_INT)throw new IOException("Android version not supported");
                JSONArray abis=manifest.getJSONArray("abis");
                boolean compatible=false;
                for(String supported:Build.SUPPORTED_ABIS)for(int i=0;i<abis.length();i++)
                    if(supported.equals(abis.optString(i)))compatible=true;
                if(!compatible){ui(()->listener.complete(null,"This update does not support your device architecture."));return;}
                long size=manifest.getLong("bytes");
                String hash=manifest.getString("sha256").toLowerCase(Locale.ROOT);
                if(size<=0||size>MAX_APK_SIZE||!hash.matches("[a-f0-9]{64}"))
                    throw new IOException("Release checksum or size mismatch");
                String notes=manifest.optString("notes","").trim();
                if(notes.length()>1800)notes=notes.substring(0,1800)+"…";
                // Pin the APK to the manifest version, not the moving latest alias.
                URL apkUrl=new URL("https://github.com/"+repo+"/releases/download/"+tag+"/"+APK);
                Release release=new Release(version,code,notes,apkUrl,size,hash);
                ui(()->listener.complete(release,null));
            }catch(Exception e){
                android.util.Log.w("IsmeUpdater","Update check failed: "+diagnostic(e));
                String error=e instanceof HttpFailure
                    ?"Could not check for updates (HTTP "+((HttpFailure)e).status+"). Try again later."
                    :"Could not check for updates. Try again later.";
                ui(()->listener.complete(null,error));
            }
        });
    }
    void cancel(){cancelled.set(true);HttpURLConnection c=activeDownload;if(c!=null)c.disconnect();}
    void download(Release release,DownloadListener listener){
        cancelled.set(false);
        worker.execute(()->{
            File temp=null;
            try{
                File dir=new File(activity.getCacheDir(),"updates");
                if(!dir.exists()&&!dir.mkdirs())throw new IOException("Cannot create update cache");
                temp=new File(dir,"isme-download.apk");
                File finished=new File(dir,APK);
                verifiedApk=null;verifiedRelease=null;
                if(finished.exists()&&!finished.delete())throw new IOException("Cannot clear previous update");
                if(dir.getUsableSpace()<release.size+16L*1024*1024)throw new IOException("Not enough storage");
                if(cancelled.get()||closed)throw new IOException("Cancelled");
                HttpURLConnection c=open(release.url);activeDownload=c;
                long total=0,last=0;MessageDigest hash=MessageDigest.getInstance("SHA-256");
                try(InputStream in=c.getInputStream();FileOutputStream out=new FileOutputStream(temp)){
                    byte[] buffer=new byte[32768];int n;
                    while((n=in.read(buffer))!=-1){
                        if(cancelled.get()||closed)throw new IOException("Cancelled");
                        total+=n;if(total>release.size)throw new IOException("APK exceeds declared size");
                        hash.update(buffer,0,n);out.write(buffer,0,n);
                        long now=android.os.SystemClock.elapsedRealtime();
                        if(now-last>=200||total==release.size){last=now;final long received=total;ui(()->listener.progress(received,release.size));}
                    }
                }finally{activeDownload=null;c.disconnect();}
                if(cancelled.get()||closed)throw new IOException("Cancelled");
                if(total!=release.size||!hex(hash.digest()).equals(release.sha256))throw new IOException("APK checksum mismatch");
                verifyArchive(temp,release);
                if(cancelled.get()||closed)throw new IOException("Cancelled");
                if(!temp.renameTo(finished))throw new IOException("Cannot save verified APK");
                verifiedApk=finished;verifiedRelease=release;
                ui(listener::ready);
            }catch(Exception e){
                if(temp!=null)temp.delete();
                final String message=cancelled.get()?"Download cancelled.":"Update failed: "+(e.getMessage()==null?"Try again.":e.getMessage());
                ui(()->listener.error(message));
            }
        });
    }
    private void verifyArchive(File apk,Release release) throws Exception{
        PackageManager pm=activity.getPackageManager();
        PackageInfo installed=pm.getPackageInfo(activity.getPackageName(),PackageManager.GET_SIGNING_CERTIFICATES);
        PackageInfo incoming=pm.getPackageArchiveInfo(apk.getAbsolutePath(),PackageManager.GET_SIGNING_CERTIFICATES);
        if(incoming==null||!activity.getPackageName().equals(incoming.packageName)||installed.signingInfo==null||incoming.signingInfo==null)
            throw new IOException("APK package or signature missing");
        Signature[] existing=installed.signingInfo.getApkContentsSigners(),offered=incoming.signingInfo.getApkContentsSigners();
        if(existing==null||offered==null||existing.length==0||!Arrays.equals(existing,offered))throw new IOException("APK signer does not match installed app");
        if(incoming.getLongVersionCode()!=release.code||incoming.getLongVersionCode()<=installed.getLongVersionCode()||!release.version.equals(incoming.versionName))
            throw new IOException("APK version does not match release");
        if(incoming.applicationInfo!=null&&incoming.applicationInfo.minSdkVersion>Build.VERSION.SDK_INT)throw new IOException("Android version not supported");
    }
    void discard(){
        awaitingInstallPermission=false;
        if(verifiedApk!=null)verifiedApk.delete();
        verifiedApk=null;verifiedRelease=null;
    }
    void install() throws Exception{
        File file=verifiedApk;Release release=verifiedRelease;
        if(file==null||!file.isFile()||release==null)throw new IOException("No verified update ready");
        if(!activity.getPackageManager().canRequestPackageInstalls()){
            awaitingInstallPermission=true;
            activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+activity.getPackageName())));
            return;
        }
        awaitingInstallPermission=false;
        // The verified file resides in app-private cache. Android's installer performs signature and compatibility checks again.
        Uri uri=FileProvider.getUriForFile(activity,activity.getPackageName()+".fileprovider",file);
        Intent intent=new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri,"application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activity.startActivity(intent);
    }
    boolean takePendingInstall(){boolean pending=awaitingInstallPermission;awaitingInstallPermission=false;return pending;}
    boolean canInstall(){return activity.getPackageManager().canRequestPackageInstalls();}
    void close(){closed=true;cancel();worker.shutdownNow();}
    private static byte[] readLimited(InputStream in,int limit) throws IOException{
        try(InputStream input=in;ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] buffer=new byte[8192];int n;
            while((n=input.read(buffer))!=-1){if(out.size()+n>limit)throw new IOException("Release metadata too large");out.write(buffer,0,n);}
            return out.toByteArray();
        }
    }
    private static String hex(byte[] bytes){
        StringBuilder value=new StringBuilder(bytes.length*2);
        for(byte b:bytes)value.append(String.format(Locale.ROOT,"%02x",b&0xff));
        return value.toString();
    }
}
