package gg.isme.tv;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;

/** Regional TMDB/JustWatch metadata. No guessed provider membership or media URLs. */
final class PlatformCatalog {
    private final CatalogCache cache;
    PlatformCatalog(CatalogCache cache){this.cache=cache;}
    private static void region(String country){
        if(!country.matches("[A-Z]{2}"))throw new IllegalArgumentException("Invalid region");
    }
    private static JSONObject result(JSONArray rows,String field,boolean hit,boolean stale)throws Exception{
        return new JSONObject().put(field,rows).put("cacheHit",hit).put("stale",stale);
    }
    JSONObject directory(String country,String token,String mode)throws Exception{
        boolean global="GLOBAL".equals(country);
        if(!global)region(country);
        CatalogCache.Entry cached=cache.read("platform_directory",country);
        boolean usable=cached!=null&&cached.fresh(30*CatalogCache.DAY);
        if("cached".equals(mode))return usable?cached.data.put("cacheHit",true).put("stale",!cached.fresh(CatalogCache.DAY)):
            result(new JSONArray(),"providers",false,true);
        if(usable&&(token.isEmpty()||(cached.fresh(CatalogCache.DAY)&&!"refresh".equals(mode))))return cached.data.put("cacheHit",true).put("stale",!cached.fresh(CatalogCache.DAY));
        if(token.isEmpty())return result(new JSONArray(),"providers",false,true);
        try{
            Map<Integer,JSONObject> providers=new LinkedHashMap<>();
            for(String kind:new String[]{"movie","tv"}){
                JSONArray rows=WatchProviders.get("/watch/providers/"+kind+(global?"":"?watch_region="+country),token).optJSONArray("results");
                if(rows==null)throw new IOException("Provider directory unavailable");
                for(int i=0;i<rows.length();i++){
                    JSONObject row=rows.optJSONObject(i);if(row==null)continue;
                    int id=row.optInt("provider_id",0);String name=row.optString("provider_name","");
                    if(id<=0||name.isEmpty())continue;
                    JSONObject p=providers.get(id);
                    if(p==null){p=new JSONObject().put("id",id).put("name",name)
                        .put("logo",SeriesCatalog.image(row,"logo_path","w185"));providers.put(id,p);}
                    // Worldwide directory is artwork only; never evidence of local availability.
                    p.put(kind,!global);
                }
            }
            JSONArray rows=new JSONArray();
            for(JSONObject p:providers.values())rows.put(p);
            JSONObject value=result(rows,"providers",false,false);
            cache.write("platform_directory",country,value);
            return value;
        }catch(Exception e){if(usable)return cached.data.put("cacheHit",true).put("stale",true);throw e;}
    }
    JSONObject discover(String country,String ids,String kind,String row,String mode,String token)throws Exception{
        region(country);
        if(!ids.matches("[1-9][0-9]{0,7}(?:\\|[1-9][0-9]{0,7}){0,7}")||
           !kind.matches("movie|tv")||!row.matches("popular|rated|recent|anime|drama|action|comedy"))
            throw new IllegalArgumentException("Invalid platform catalog");
        String key=country+":"+ids+":"+kind+":"+row;
        CatalogCache.Entry cached=cache.read("platform_catalog",key);
        boolean usable=cached!=null&&cached.fresh(30*CatalogCache.DAY);
        if("cached".equals(mode))return usable?cached.data.put("cacheHit",true).put("stale",!cached.fresh(CatalogCache.DAY)):
            result(new JSONArray(),"items",false,true);
        if(usable&&(token.isEmpty()||(cached.fresh(CatalogCache.DAY)&&!"refresh".equals(mode))))return cached.data.put("cacheHit",true).put("stale",!cached.fresh(CatalogCache.DAY));
        if(token.isEmpty())throw new IOException("TMDB connection required for regional platform catalogs");
        try{
            String sort="rated".equals(row)?"vote_average.desc&vote_count.gte=50":
                "recent".equals(row)?("movie".equals(kind)?"primary_release_date.desc":"first_air_date.desc"):"popularity.desc";
            String date=new java.text.SimpleDateFormat("yyyy-MM-dd",java.util.Locale.US).format(new java.util.Date());
            String path="/discover/"+kind+"?include_adult=false&watch_region="+country+
                "&with_watch_providers="+MediaCatalog.encode(ids)+"&with_watch_monetization_types=flatrate%7Cfree%7Cads"+
                "&sort_by="+sort+"&"+("movie".equals(kind)?"primary_release_date.lte":"first_air_date.lte")+"="+date;
            if("anime".equals(row))path+="&with_genres=16&with_origin_country=JP";
            else if("drama".equals(row))path+="&with_genres=18";
            else if("action".equals(row))path+="&with_genres="+("movie".equals(kind)?"28":"10759");
            else if("comedy".equals(row))path+="&with_genres=35";
            JSONArray raw=WatchProviders.get(path,token).optJSONArray("results");
            if(raw==null)throw new IOException("Catalog unavailable");
            JSONArray items="tv".equals(kind)?SeriesCatalog.tmdbRows(raw,"anime".equals(row)):movieRows(raw);
            JSONObject value=result(items,"items",false,false);
            cache.write("platform_catalog",key,value);
            return value;
        }catch(Exception e){if(usable)return cached.data.put("cacheHit",true).put("stale",true);throw e;}
    }
    static JSONArray movieRows(JSONArray raw)throws Exception{
        JSONArray items=new JSONArray();
        for(int i=0;i<raw.length()&&items.length()<40;i++){
            JSONObject m=raw.optJSONObject(i);if(m==null||m.optBoolean("adult"))continue;
            int id=m.optInt("id",0);String title=m.optString("title",""),date=m.optString("release_date","");
            if(id<=0||title.isEmpty())continue;
            items.put(new JSONObject().put("id","tmdb:movie:"+id).put("tmdbId",id).put("type","Movie")
                .put("title",title).put("description",m.optString("overview",""))
                .put("poster",SeriesCatalog.image(m,"poster_path","w342"))
                .put("backdrop",SeriesCatalog.image(m,"backdrop_path","w1280"))
                .put("year",date.length()>=4?date.substring(0,4):""));
        }
        return items;
    }
    String movieImdb(int tmdb,String token)throws Exception{
        if(tmdb<=0)throw new IllegalArgumentException("Invalid movie ID");
        String key="movie:"+tmdb;
        CatalogCache.Entry saved=cache.read("external_ids",key);
        String imdb=saved==null?"":saved.data.optString("imdb","");
        if(imdb.matches("tt[0-9]{7,10}"))return imdb;
        JSONObject data=WatchProviders.get("/movie/"+tmdb+"/external_ids",token);
        imdb=data.optString("imdb_id","");
        if(!imdb.matches("tt[0-9]{7,10}"))throw new IOException("No IMDb mapping for this movie");
        cache.write("external_ids",key,new JSONObject().put("imdb",imdb));return imdb;
    }
}
