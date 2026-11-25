package gg.isme.tv;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.IOException;
import java.util.TreeSet;

/** On-device TV metadata only. A title's metadata ID is not a playable media source. */
final class SeriesCatalog {
    private final CatalogCache cache;
    SeriesCatalog(CatalogCache cache){this.cache=cache;}

    static boolean validId(String id){return id.matches("imdb:tt[0-9]{7,10}|tmdb:tv:[1-9][0-9]{0,8}");}
    static String image(JSONObject o,String key,String size){
        String path=o.optString(key,"");
        return path.matches("/[a-zA-Z0-9_.-]+")?"https://image.tmdb.org/t/p/"+size+path:"";
    }
    static boolean japaneseAnimation(JSONObject row){
        JSONArray genres=row.optJSONArray("genre_ids"), countries=row.optJSONArray("origin_country");
        boolean animation=false,japan=false;
        if(genres!=null)for(int i=0;i<genres.length();i++)animation|=genres.optInt(i)==16;
        if(countries!=null)for(int i=0;i<countries.length();i++)japan|="JP".equals(countries.optString(i));
        return animation&&japan;
    }
    private static boolean animeMeta(JSONObject m){
        JSONArray genres=m.optJSONArray("genres");if(genres==null)genres=m.optJSONArray("genre");
        if(genres==null)return false;
        boolean animation=false;
        for(int i=0;i<genres.length();i++){
            if("Anime".equalsIgnoreCase(genres.optString(i)))return true;
            animation|="Animation".equalsIgnoreCase(genres.optString(i));
        }
        String country=m.optString("country","").toLowerCase(java.util.Locale.ROOT);
        return animation&&(country.contains("japan")||country.equals("jp"));
    }
    static JSONArray tmdbRows(JSONArray raw,boolean animeOnly)throws Exception{
        JSONArray items=new JSONArray();
        if(raw==null)throw new IOException("Invalid TV catalog response");
        for(int i=0;i<raw.length()&&items.length()<50;i++){
            JSONObject m=raw.optJSONObject(i);if(m==null||m.optBoolean("adult"))continue;
            int id=m.optInt("id",0);String name=m.optString("name","");
            boolean anime=japaneseAnimation(m);
            if(id<=0||name.isEmpty()||(animeOnly&&!anime))continue;
            String date=m.optString("first_air_date","");
            items.put(new JSONObject().put("id","tmdb:tv:"+id).put("tmdbId",id)
                .put("title",name).put("type",anime?"Anime":"Series").put("description",m.optString("overview",""))
                .put("poster",image(m,"poster_path","w342")).put("backdrop",image(m,"backdrop_path","w1280"))
                .put("year",date.length()>=4?date.substring(0,4):"").put("ratingLabel",m.optDouble("vote_average",0)>0?String.format(java.util.Locale.US,"%.1f",m.optDouble("vote_average")):""));
        }
        return items;
    }
    private static JSONArray cinemetaRows(String collection,String query)throws Exception{
        boolean anime=collection.startsWith("anime");
        String suffix=query.isEmpty()?(anime?"top/genre=Animation":collection.endsWith("rated")?"imdbRating":"top")
            :"top/search="+MediaCatalog.encode(query);
        JSONArray raw=MediaCatalog.getJson(MediaCatalog.CINEMETA+"/catalog/series/"+suffix+".json",1024*1024).optJSONArray("metas");
        if(raw==null)throw new IOException("Invalid series catalog");
        JSONArray items=new JSONArray();
        for(int i=0;i<raw.length()&&items.length()<50;i++){
            JSONObject m=raw.optJSONObject(i);if(m==null||!"series".equals(m.optString("type")))continue;
            String id=m.optString("id"),name=m.optString("name");
            boolean isAnime=animeMeta(m);
            if(!id.matches("tt[0-9]{7,10}")||name.isEmpty()||(anime&&!isAnime))continue;
            items.put(new JSONObject().put("id","imdb:"+id).put("title",name).put("type",isAnime?"Anime":"Series")
                .put("description",m.optString("description")).put("poster",m.optString("poster"))
                .put("backdrop",m.optString("background")).put("year",m.optString("releaseInfo",""))
                .put("genres",m.optJSONArray("genres")==null?new JSONArray():m.optJSONArray("genres")));
        }
        return items;
    }
    JSONObject catalog(String collection,String query,String mode,String token)throws Exception{
        if(!collection.matches("series|series_rated|series_pinoy|anime|anime_rated"))throw new IllegalArgumentException("Invalid TV collection");
        boolean search=!query.isEmpty(),anime=collection.startsWith("anime"),pinoy="series_pinoy".equals(collection);
        String key=collection;
        CatalogCache.Entry saved=search?null:cache.read("tv_catalog",key);
        boolean usable=saved!=null&&saved.fresh(30*CatalogCache.DAY);
        if("cached".equals(mode)&&!search)return (usable?saved.data:new JSONObject().put("items",new JSONArray()))
            .put("cacheHit",usable).put("stale",!usable||!saved.fresh(CatalogCache.DAY)||(!token.isEmpty()&&!"tmdb".equals(saved.data.optString("source"))));
        if(!search&&usable&&saved.fresh(CatalogCache.DAY)&&!"refresh".equals(mode)&&(token.isEmpty()||"tmdb".equals(saved.data.optString("source"))))
            return saved.data.put("cacheHit",true).put("stale",false);
        try{
            JSONArray items;String source="cinemeta";
            if(!token.isEmpty()){
                try{
                    String path=search?"/search/tv?include_adult=false&query="+MediaCatalog.encode(query):
                        "/discover/tv?include_adult=false&sort_by="+(collection.endsWith("rated")?"vote_average.desc&vote_count.gte=100":"popularity.desc")+
                        (anime?"&with_genres=16&with_origin_country=JP":pinoy?"&with_origin_country=PH":"");
                    items=tmdbRows(WatchProviders.get(path,token).optJSONArray("results"),anime);
                    source="tmdb";
                }catch(Exception e){if(pinoy)throw e;items=cinemetaRows(collection,query);}
            }else items=pinoy?new JSONArray():cinemetaRows(collection,query);
            if(items.length()==0&&usable)return saved.data.put("cacheHit",true).put("stale",true);
            JSONObject value=new JSONObject().put("items",items).put("source",source);
            if(!search&&items.length()>0)cache.write("tv_catalog",key,value);
            return value.put("cacheHit",false).put("stale",false);
        }catch(Exception e){
            if(usable)return saved.data.put("cacheHit",true).put("stale",true);
            throw e;
        }
    }
    private JSONObject cinemeta(String id)throws Exception{
        if(!id.startsWith("imdb:"))id="imdb:"+imdbId(id,"");
        CatalogCache.Entry entry=cache.read("episodes",id+":meta");
        if(entry!=null&&entry.fresh(7*CatalogCache.DAY))return entry.data;
        try{
            JSONObject meta=MediaCatalog.getJson(MediaCatalog.CINEMETA+"/meta/series/"+id.substring(5)+".json",2*1024*1024).optJSONObject("meta");
            if(meta==null||meta.optJSONArray("videos")==null)throw new IOException("Episode metadata unavailable");
            cache.write("episodes",id+":meta",meta);return meta;
        }catch(Exception e){if(entry!=null&&entry.fresh(30*CatalogCache.DAY))return entry.data;throw e;}
    }
    private int tmdbId(String id,String token)throws Exception{
        if(id.startsWith("tmdb:tv:"))return Integer.parseInt(id.substring(8));
        JSONArray rows=WatchProviders.get("/find/"+id.substring(5)+"?external_source=imdb_id",token).optJSONArray("tv_results");
        JSONObject row=rows==null?null:rows.optJSONObject(0);
        return row==null?0:row.optInt("id",0);
    }
    // Resolve the parent series identity through metadata, not a guessed episode number.
    String imdbId(String id,String token)throws Exception{
        if(!validId(id))throw new IllegalArgumentException("Invalid series ID");
        if(id.startsWith("imdb:"))return id.substring(5);
        CatalogCache.Entry saved=cache.read("episodes",id+":external");
        String imdb=saved==null?"":saved.data.optString("imdb","");
        if(imdb.matches("tt[0-9]{7,10}"))return imdb;
        if(token.isEmpty())throw new IOException("TMDB connection required to identify this series");
        JSONObject ids=WatchProviders.get("/tv/"+tmdbId(id,token)+"/external_ids",token);
        imdb=ids.optString("imdb_id","");
        if(!imdb.matches("tt[0-9]{7,10}"))throw new IOException("No IMDb mapping for this series");
        cache.write("episodes",id+":external",new JSONObject().put("imdb",imdb));
        return imdb;
    }
    JSONObject seasons(String id,String token)throws Exception{
        if(!validId(id))throw new IllegalArgumentException("Invalid series ID");
        CatalogCache.Entry entry=cache.read("episodes",id+":seasons");
        if(entry!=null&&entry.fresh(CatalogCache.DAY))return entry.data;
        JSONArray seasons=new JSONArray();
        try{
            boolean found=false;
            if(!token.isEmpty())try{
                int tmdb=tmdbId(id,token);
                JSONArray rows=tmdb>0?WatchProviders.get("/tv/"+tmdb,token).optJSONArray("seasons"):null;
                if(rows!=null){for(int i=0;i<rows.length();i++){
                    JSONObject m=rows.optJSONObject(i);if(m==null)continue;
                    int n=m.optInt("season_number",-1);if(n<0||m.optInt("episode_count",0)<=0)continue;
                    seasons.put(new JSONObject().put("number",n).put("name",m.optString("name","Season "+n)));
                }found=seasons.length()>0;}
            }catch(Exception ignored){}
            if(!found){
                TreeSet<Integer> numbers=new TreeSet<>();
                JSONArray videos=cinemeta(id).optJSONArray("videos");
                for(int i=0;i<videos.length();i++){JSONObject m=videos.optJSONObject(i);if(m!=null&&m.optInt("season",-1)>=0)numbers.add(m.optInt("season"));}
                for(int n:numbers)seasons.put(new JSONObject().put("number",n).put("name",n==0?"Specials":"Season "+n));
            }
            JSONObject value=new JSONObject().put("seasons",seasons);
            if(seasons.length()>0)cache.write("episodes",id+":seasons",value);
            return value;
        }catch(Exception e){if(entry!=null&&entry.fresh(30*CatalogCache.DAY))return entry.data;throw e;}
    }
    JSONObject episodes(String id,int season,String token)throws Exception{
        if(!validId(id)||season<0||season>10000)throw new IllegalArgumentException("Invalid season");
        String key=id+":season:"+season;
        CatalogCache.Entry entry=cache.read("episodes",key);
        if(entry!=null&&entry.fresh(CatalogCache.DAY))return entry.data;
        JSONArray episodes=new JSONArray();
        try{
            boolean found=false;
            if(!token.isEmpty())try{
                int tmdb=tmdbId(id,token);
                JSONArray rows=tmdb>0?WatchProviders.get("/tv/"+tmdb+"/season/"+season,token).optJSONArray("episodes"):null;
                if(rows!=null){for(int i=0;i<rows.length();i++){
                    JSONObject m=rows.optJSONObject(i);if(m==null)continue;
                    int n=m.optInt("episode_number",-1);if(n<0)continue;
                    episodes.put(new JSONObject().put("number",n).put("title",m.optString("name","Episode "+n))
                        .put("description",m.optString("overview","")).put("thumbnail",image(m,"still_path","w780"))
                        .put("runtime",m.optInt("runtime",0)).put("airDate",m.optString("air_date","")));
                }found=episodes.length()>0;}
            }catch(Exception ignored){}
            if(!found){
                JSONArray rows=cinemeta(id).optJSONArray("videos");
                for(int i=0;i<rows.length();i++){
                    JSONObject m=rows.optJSONObject(i);if(m==null||m.optInt("season",-1)!=season)continue;
                    int n=m.optInt("episode",-1);if(n<0)continue;
                    episodes.put(new JSONObject().put("number",n).put("title",m.optString("title","Episode "+n))
                        .put("description",m.optString("overview",m.optString("description","")))
                        .put("thumbnail",m.optString("thumbnail","")).put("runtime",0).put("airDate",m.optString("released","")));
                }
            }
            JSONObject value=new JSONObject().put("episodes",episodes);
            if(episodes.length()>0)cache.write("episodes",key,value);
            return value;
        }catch(Exception e){if(entry!=null&&entry.fresh(30*CatalogCache.DAY))return entry.data;throw e;}
    }
}
