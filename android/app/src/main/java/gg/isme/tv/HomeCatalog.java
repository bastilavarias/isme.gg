package gg.isme.tv;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.IOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Editorial metadata only. Weekly rank is TMDB's rolling seven-day order, not app viewership. */
final class HomeCatalog {
    private final CatalogCache cache;
    HomeCatalog(CatalogCache cache){this.cache=cache;}
    static boolean allowed(String key){return key.matches(
        "weekly_movies|weekly_tv|weekly_series|weekly_anime|recent_home|pinoy_home|korean_home|"+
        "page_movies_(recent|action|comedy|horror|scifi|romance|rated|gems|classics)|"+
        "page_series_(recent|airing|binge|crime|drama|comedy|korean|rated)|"+
        "page_anime_(airing|recent|action|fantasy|romance|movies|rated)|"+
        "page_pinoy_(movies|series|recent|romance|comedy|action|horror|indie|classics)");}
    private static boolean weekly(String key){return key.startsWith("weekly_");}
    private static JSONObject result(JSONArray items,String source,boolean hit,boolean stale)throws Exception{
        return new JSONObject().put("items",items).put("source",source).put("cacheHit",hit).put("stale",stale);
    }
    private static JSONArray fetch(String path,boolean tv,String token)throws Exception{
        JSONArray raw=WatchProviders.get(path,token).optJSONArray("results");
        if(raw==null)throw new IOException("Invalid editorial catalog response");
        return tv?SeriesCatalog.tmdbRows(raw,false):PlatformCatalog.movieRows(raw);
    }
    private static JSONArray bounded(JSONArray rows,int max)throws Exception{
        JSONArray items=new JSONArray();Set<String> ids=new HashSet<>();
        for(int i=0;i<rows.length()&&items.length()<max;i++){
            JSONObject m=rows.optJSONObject(i);
            if(m!=null&&!m.optString("id").isEmpty()&&ids.add(m.optString("id")))items.put(m);
        }
        return items;
    }
    private static JSONArray merge(JSONArray movies,JSONArray tv,int max)throws Exception{
        JSONArray mixed=new JSONArray();
        for(int i=0;i<Math.max(movies.length(),tv.length());i++){
            if(i<movies.length())mixed.put(movies.getJSONObject(i));
            if(i<tv.length())mixed.put(tv.getJSONObject(i));
        }
        return bounded(mixed,max);
    }
    private JSONArray recent(String token)throws Exception{
        LocalDate today=LocalDate.now(),since=today.minusDays(90);
        String dates="&include_adult=false&sort_by=primary_release_date.desc&primary_release_date.gte="+since+"&primary_release_date.lte="+today+"&vote_count.gte=5";
        JSONArray movies=fetch("/discover/movie?"+dates.substring(1),false,token);
        JSONArray shows=fetch("/discover/tv?include_adult=false&sort_by=first_air_date.desc&first_air_date.gte="+since+"&first_air_date.lte="+today+"&vote_count.gte=5",true,token);
        List<JSONObject> list=new ArrayList<>();
        JSONArray mixed=merge(movies,shows,40);
        for(int i=0;i<mixed.length();i++){
            JSONObject item=mixed.getJSONObject(i);
            try{
                LocalDate date=LocalDate.parse(item.optString("releaseDate"));
                if(!date.isBefore(since)&&!date.isAfter(today))list.add(item);
            }catch(java.time.DateTimeException ignored){}
        }
        list.sort(Comparator.comparing((JSONObject m)->m.optString("releaseDate")).reversed());
        JSONArray result=new JSONArray();
        for(JSONObject m:list){if(result.length()==24)break;result.put(m);}
        return result;
    }
    private JSONArray regional(String key,String token)throws Exception{
        String country="pinoy_home".equals(key)?"PH":"KR";
        JSONArray movies=fetch("/discover/movie?include_adult=false&sort_by=popularity.desc&with_origin_country="+country,false,token);
        JSONArray shows=fetch("/discover/tv?include_adult=false&sort_by=popularity.desc&with_origin_country="+country,true,token);
        if("PH".equals(country)){mark(movies,"pinoy");mark(shows,"pinoy");}
        return merge(movies,shows,30);
    }
    private static void mark(JSONArray rows,String field)throws Exception{
        for(int i=0;i<rows.length();i++)rows.getJSONObject(i).put(field,true);
    }
    private static JSONArray selectTv(JSONArray rows,boolean anime)throws Exception{
        JSONArray items=new JSONArray();
        for(int i=0;i<rows.length();i++){
            JSONObject m=rows.getJSONObject(i);
            if((anime?"Anime":"Series").equals(m.optString("type")))items.put(m);
        }
        return items;
    }
    private static JSONArray append(JSONArray first,JSONArray second)throws Exception{
        for(int i=0;i<second.length();i++)first.put(second.getJSONObject(i));
        return first;
    }
    // Filter the actual weekly trending TV feed, preserving its ordering.
    // Bound discovery to two pages; don't fill missing ranks with popularity.
    private JSONArray weeklyTv(boolean anime,String token)throws Exception{
        JSONArray items=selectTv(fetch("/trending/tv/week?page=1",true,token),anime);
        if(items.length()<10){
            try{append(items,selectTv(fetch("/trending/tv/week?page=2",true,token),anime));}
            catch(Exception e){if(items.length()==0)throw e;}
        }
        return bounded(items,10);
    }
    private static String recentDates(boolean tv,LocalDate today){
        String field=tv?"first_air_date":"primary_release_date";
        return "&"+field+".gte="+today.minusDays(90)+"&"+field+".lte="+today+"&vote_count.gte=5";
    }
    private static JSONArray dateWindow(JSONArray items,LocalDate from,LocalDate through)throws Exception{
        JSONArray kept=new JSONArray();
        for(int i=0;i<items.length();i++){
            JSONObject item=items.getJSONObject(i);
            try{
                LocalDate date=LocalDate.parse(item.optString("releaseDate"));
                if(!date.isBefore(from)&&!date.isAfter(through))kept.put(item);
            }catch(java.time.DateTimeException ignored){}
        }
        return kept;
    }
    // Resolve exact keyword names from the metadata service rather than
    // assuming a genre is proof of independent production or slice of life.
    private String keyword(String name,String token)throws Exception{
        String cacheKey="keyword:"+name;
        CatalogCache.Entry entry=cache.read("editorial_keyword",cacheKey);
        if(entry!=null&&entry.fresh(7*CatalogCache.DAY))return entry.data.optString("id","");
        JSONArray rows=WatchProviders.get("/search/keyword?query="+MediaCatalog.encode(name),token).optJSONArray("results");
        if(rows==null)return "";
        for(int i=0;i<rows.length();i++){
            JSONObject row=rows.optJSONObject(i);
            if(row!=null&&name.equalsIgnoreCase(row.optString("name"))&&row.optInt("id")>0){
                String id=String.valueOf(row.optInt("id"));
                cache.write("editorial_keyword",cacheKey,new JSONObject().put("id",id));return id;
            }
        }
        return "";
    }
    private JSONArray pageRows(String key,String token)throws Exception{
        LocalDate today=LocalDate.now();
        boolean anime=key.startsWith("page_anime_"),pinoy=key.startsWith("page_pinoy_");
        boolean tv=key.startsWith("page_series_")||(anime&&!"page_anime_movies".equals(key))||"page_pinoy_series".equals(key);
        String sort="popularity.desc",filters="";
        if(anime)filters="&with_origin_country=JP&with_original_language=ja";
        if(pinoy)filters="&with_origin_country=PH";
        String genre=anime?"16":"";
        boolean recent=key.endsWith("_recent"),classic=key.endsWith("_classics");
        if(!tv)filters+="&include_video=false";
        switch(key){
            case "page_movies_recent":case "page_series_recent":case "page_anime_recent":case "page_pinoy_recent":
                sort=tv?"first_air_date.desc":"primary_release_date.desc";filters+=recentDates(tv,today);break;
            case "page_movies_action":genre="28%7C12";break;
            case "page_movies_comedy":case "page_pinoy_comedy":case "page_series_comedy":genre="35";break;
            case "page_movies_horror":genre="27%7C53";break;
            case "page_pinoy_horror":genre="27";break;
            case "page_movies_scifi":genre="878";break;
            case "page_movies_romance":case "page_pinoy_romance":genre="10749";break;
            case "page_pinoy_action":genre="28";break;
            case "page_movies_rated":case "page_series_rated":case "page_anime_rated":
                sort="vote_average.desc";filters+="&vote_count.gte=100";break;
            case "page_movies_gems":
                sort="vote_average.desc";filters+="&vote_average.gte=7&vote_count.gte=30&vote_count.lte=500";break;
            case "page_movies_classics":case "page_pinoy_classics":
                filters+="&primary_release_date.lte=1999-12-31&vote_count.gte=1";break;
            case "page_series_airing":case "page_anime_airing":
                filters+="&with_status=0&air_date.gte="+today.minusDays(7)+"&air_date.lte="+today.plusDays(7);break;
            case "page_series_binge":filters+="&with_status=3&vote_average.gte=7&vote_count.gte=30";break;
            case "page_series_crime":genre="80%7C9648";break;
            case "page_series_drama":genre="18";break;
            case "page_series_korean":filters+="&with_origin_country=KR";genre="18";break;
            case "page_anime_action":genre="16,10759";break;
            case "page_anime_fantasy":genre="16,10765";break;
            case "page_anime_romance":{
                String slice=keyword("slice of life",token);
                String romance=keyword("romance",token);
                String ids=slice.isEmpty()?romance:romance.isEmpty()?slice:slice+"%7C"+romance;
                if(ids.isEmpty())return new JSONArray();
                filters+="&with_keywords="+ids;break;
            }
            case "page_pinoy_indie":{
                String id=keyword("independent film",token);
                if(id.isEmpty())return new JSONArray();
                filters+="&with_keywords="+id;break;
            }
            case "page_pinoy_movies":case "page_pinoy_series":case "page_anime_movies":break;
            default:throw new IllegalArgumentException("Unknown page collection");
        }
        if(!genre.isEmpty())filters+="&with_genres="+genre;
        String path="/discover/"+(tv?"tv":"movie")+"?include_adult=false&sort_by="+sort+filters;
        JSONArray items=fetch(path,tv,token);
        if(tv)items=selectTv(items,anime);
        if(pinoy)mark(items,"pinoy");
        if(anime&&!tv)mark(items,"animeFilm");
        if(recent)items=dateWindow(items,today.minusDays(90),today);
        if(classic)items=dateWindow(items,LocalDate.of(1880,1,1),LocalDate.of(1999,12,31));
        return bounded(items,24);
    }
    JSONObject catalog(String key,String mode,String token)throws Exception{
        if(!allowed(key))throw new IllegalArgumentException("Unknown home collection");
        if(token.isEmpty())return result(new JSONArray(),"",false,false);
        long ttl=weekly(key)?3*CatalogCache.HOUR:CatalogCache.DAY;
        boolean timeSensitive=key.endsWith("_recent")||key.endsWith("_airing")||"recent_home".equals(key);
        long maxAge=weekly(key)?CatalogCache.DAY:(timeSensitive?3*CatalogCache.DAY:7*CatalogCache.DAY);
        CatalogCache.Entry saved=cache.read("home_catalog",key);
        boolean usable=saved!=null&&saved.fresh(maxAge);
        if("cached".equals(mode)||(!"refresh".equals(mode)&&usable&&saved.fresh(ttl))){
            if(usable)return saved.data.put("cacheHit",true).put("stale",!saved.fresh(ttl));
            return result(new JSONArray(),"",false,true);
        }
        try{
            JSONArray items;
            switch(key){
                case "weekly_movies":items=bounded(fetch("/trending/movie/week",false,token),10);break;
                case "weekly_tv":items=bounded(fetch("/trending/tv/week",true,token),10);break;
                case "weekly_series":items=weeklyTv(false,token);break;
                case "weekly_anime":items=weeklyTv(true,token);break;
                case "recent_home":items=recent(token);break;
                case "pinoy_home":case "korean_home":items=regional(key,token);break;
                default:items=pageRows(key,token);
            }
            if(items.length()==0&&usable)return saved.data.put("cacheHit",true).put("stale",true);
            JSONObject value=result(items,weekly(key)?"tmdb_weekly":"tmdb",false,false);
            if(items.length()>0)cache.write("home_catalog",key,value);
            return value;
        }catch(Exception e){
            if(usable)return saved.data.put("cacheHit",true).put("stale",true);
            throw e;
        }
    }
}
