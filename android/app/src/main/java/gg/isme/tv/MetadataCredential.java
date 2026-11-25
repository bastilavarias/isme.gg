package gg.isme.tv;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import java.nio.charset.StandardCharsets;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** User-supplied read token, encrypted at rest using the device's Android Keystore. */
final class MetadataCredential {
    private static final String ALIAS="isme_tmdb_read_v1";
    private static SharedPreferences prefs(Context c){return c.getSharedPreferences("metadata_credential",Context.MODE_PRIVATE);}
    private static SecretKey key(boolean create)throws Exception{
        KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);
        if(store.containsAlias(ALIAS))return (SecretKey)store.getKey(ALIAS,null);
        if(!create)return null;
        KeyGenerator gen=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        gen.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return gen.generateKey();
    }
    static String read(Context c){
        try{
            String value=prefs(c).getString("cipher","");
            if(value.isEmpty())return "";
            String[] fields=value.split(":",2);SecretKey key=key(false);
            if(fields.length!=2||key==null)return "";
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE,key,new GCMParameterSpec(128,Base64.decode(fields[0],Base64.NO_WRAP)));
            return new String(cipher.doFinal(Base64.decode(fields[1],Base64.NO_WRAP)),StandardCharsets.UTF_8);
        }catch(Exception e){return "";}
    }
    static void save(Context c,String token)throws Exception{
        if(token.isEmpty()){if(!prefs(c).edit().remove("cipher").commit())throw new java.io.IOException("Could not clear credential");return;}
        if(token.length()>2048||!token.matches("[A-Za-z0-9._~+/-]+=*"))throw new IllegalArgumentException("Invalid read token");
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE,key(true));
        String iv=Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP);
        String encrypted=Base64.encodeToString(cipher.doFinal(token.getBytes(StandardCharsets.UTF_8)),Base64.NO_WRAP);
        if(!prefs(c).edit().putString("cipher",iv+":"+encrypted).commit())throw new java.io.IOException("Could not save credential");
    }
}
