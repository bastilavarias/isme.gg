package gg.isme.tv;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/** Official TMDB/JustWatch regional subscription availability, not exclusivity rights. */
final class WatchProviders {
    private final CatalogCache cache;
    WatchProviders(CatalogCache cache) { this.cache = cache; }

    JSONObject lookup(String imdb, int tmdb, String country, String token, boolean tv) throws Exception {
        if ((tmdb<=0&&!imdb.matches("tt[0-9]{7,10}")) || !country.matches("[A-Z]{2}"))
            throw new IllegalArgumentException("Invalid movie or region");
        String key = country + ":" + (tv?"tv:":"") + (imdb.isEmpty()?"tmdb:"+tmdb:imdb);
        CatalogCache.Entry entry = cache.read("provider", key);
        if (entry != null && entry.fresh(CatalogCache.DAY)) return entry.data;
        if (token.isEmpty()) return new JSONObject().put("provider","");
        if (token.length()>2048 || !token.matches("[A-Za-z0-9._~+/-]+=*"))
            throw new IllegalArgumentException("Invalid TMDB read token");
        if (tmdb <= 0 && entry != null) tmdb = entry.data.optInt("tmdbId",0);
        if (tmdb <= 0) {
            JSONArray movies = get("/find/"+imdb+"?external_source=imdb_id",token).optJSONArray(tv?"tv_results":"movie_results");
            JSONObject movie = movies == null ? null : movies.optJSONObject(0);
            tmdb = movie == null ? 0 : movie.optInt("id",0);
        }
        String provider = "";
        if (tmdb > 0) {
            JSONObject results = get((tv?"/tv/":"/movie/")+tmdb+"/watch/providers",token).optJSONObject("results");
            if (results == null) throw new IOException("Invalid provider response");
            JSONObject region = results.optJSONObject(country);
            provider = singleSubscription(region);
        }
        JSONObject value = new JSONObject().put("provider",provider).put("tmdbId",tmdb);
        cache.write("provider",key,value);
        return value;
    }

    static String singleSubscription(JSONObject region) {
        if (region == null) return "";
        JSONArray list = region.optJSONArray("flatrate");
        Map<Integer,String> unique = new LinkedHashMap<>();
        if (list != null) for(int i=0;i<list.length();i++){
            JSONObject row=list.optJSONObject(i);
            if(row==null)continue;
            int id=row.optInt("provider_id",0);
            String name=row.optString("provider_name","").trim();
            if(id<=0 || name.isEmpty())return "";
            unique.put(id,name);
        }
        if(unique.size()!=1)return "";
        // Other free/ad-supported options invalidate the single subscription badge.
        for(String kind:new String[]{"free","ads"}){
            JSONArray alternative=region.optJSONArray(kind);
            if(alternative!=null)for(int i=0;i<alternative.length();i++){
                JSONObject item=alternative.optJSONObject(i);
                if(item==null||!unique.containsKey(item.optInt("provider_id",0)))return "";
            }
        }
        String name=unique.values().iterator().next();
        if(name.equals("Amazon Prime Video"))return "Prime Video";
        if(name.equals("Netflix Standard with Ads"))return "Netflix";
        return name.length()<=32?name:"";
    }

    static JSONObject get(String path, String token) throws Exception {
        if(token.isEmpty()||token.length()>2048||!token.matches("[A-Za-z0-9._~+/-]+=*"))throw new IOException("Valid TMDB read token required");
        // Existing v3 keys use a query parameter; v4 read tokens use Bearer.
        // Never include the authenticated URL in error messages or logs.
        boolean apiKey=token.matches("[0-9a-fA-F]{32}");
        String requestPath=apiKey?path+(path.contains("?")?"&":"?")+"api_key="+token:path;
        HttpURLConnection c;
        try{c=(HttpURLConnection)new URL("https://api.themoviedb.org/3"+requestPath).openConnection();}
        catch(IOException e){throw new IOException("Provider connection failed");}
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(8000);c.setReadTimeout(8000);
        if(!apiKey)c.setRequestProperty("Authorization","Bearer "+token);
        c.setRequestProperty("Accept","application/json");
        try {
            int code=c.getResponseCode();
            if(code!=200)throw new IOException("Provider service HTTP "+code);
            try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){
                byte[] buffer=new byte[4096];int n;
                while((n=in.read(buffer))!=-1){
                    if(out.size()+n>512*1024)throw new IOException("Provider response too large");
                    out.write(buffer,0,n);
                }
                return new JSONObject(new String(out.toByteArray(),StandardCharsets.UTF_8));
            }
        } catch(IOException e){
            String message=e.getMessage();
            // Retain only our own sanitized status codes; transport errors may contain URLs.
            if(message!=null&&message.matches("Provider service HTTP [0-9]{3}|Provider response too large"))throw e;
            throw new IOException("Provider connection failed");
        } finally {c.disconnect();}
    }
}
