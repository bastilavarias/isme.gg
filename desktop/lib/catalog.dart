import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ismegg/engine.dart';
import 'episode_model.dart';

enum DesktopPage { home, movies, series, search, saved }

/// Desktop metadata adapter. Deliberately separate from Android MethodChannels.
/// It never resolves media sources or claims a title is available to play.
abstract interface class DesktopCatalog {
  Future<List<Movie>> browse(DesktopPage page,{String query=''});
  void close();
}
class CinemetaDesktopCatalog implements DesktopCatalog {
  CinemetaDesktopCatalog({http.Client? client}):_client=client??http.Client();
  final http.Client _client;
  static const host='v3-cinemeta.strem.io';
  @override Future<List<Movie>> browse(DesktopPage page,{String query=''}) async {
    if(page==DesktopPage.saved)return [];
    final q=query.trim();
    if(page==DesktopPage.search&&q.isEmpty)return [];
    final types=page==DesktopPage.series?['series']:(page==DesktopPage.search||page==DesktopPage.home)?['movie','series']:['movie'];
    final batches=await Future.wait(types.map((type)=>_fetch(type,q)));
    final seen=<String>{};
    return batches.expand((x)=>x).where((m)=>seen.add(m.id)).toList();
  }
  Future<List<Movie>> _fetch(String type,String query)async{
    final suffix=query.isEmpty?'':'/search=${Uri.encodeComponent(query)}';
    final url=Uri.parse('https://$host/catalog/$type/top$suffix.json');
    final request=await _client.send(http.Request('GET',url)..headers['Accept']='application/json')
      .timeout(const Duration(seconds:15));
    final buffer=<int>[];
    await for(final chunk in request.stream.timeout(const Duration(seconds:15))){
      if(buffer.length+chunk.length>1024*1024)throw const FormatException('Catalog response too large');
      buffer.addAll(chunk);
    }
    if(request.statusCode!=200)throw StateError('Catalog unavailable (HTTP ${request.statusCode})');
    final data=jsonDecode(utf8.decode(buffer));
    if(data is! Map||data['metas'] is! List)throw const FormatException('Invalid catalog response');
    return parseMetas(data['metas'] as List,type);
  }
  static List<Movie> parseMetas(List rows,String type){
    String field(Object? value)=>value?.toString().trim()??'';
    String image(Object? value){
      final url=Uri.tryParse(field(value));
      return url!=null&&url.scheme=='https'&&url.host.isNotEmpty?url.toString():'';
    }
    final movies=<Movie>[];
    for(final row in rows){
      if(row is! Map||row['type']!=type)continue;
      final id=field(row['id']), title=field(row['name']);
      if(!RegExp(r'^tt[0-9]{7,10}$').hasMatch(id)||title.isEmpty)continue;
      movies.add(Movie.fromJson({
        'id':'imdb:$id','title':title,'type':type=='series'?'Series':'Movie',
        'poster':image(row['poster']),'backdrop':image(row['background']),
        'description':field(row['description']),'year':field(row['releaseInfo']??row['year']),
        'genres':row['genres']??row['genre'],'rating':field(row['imdbRating']),
      }));
      if(movies.length==50)break;
    }
    return movies;
  }
  Future<List<DesktopEpisode>> episodes(Movie movie)async{
    if(!RegExp(r'^imdb:tt[0-9]{7,10}$').hasMatch(movie.id))return [];
    final id=movie.id.substring(5);
    final response=await _client.get(Uri.https(host,'/meta/series/$id.json')).timeout(const Duration(seconds:15));
    if(response.statusCode!=200||response.bodyBytes.length>4*1024*1024)throw StateError('Episode list unavailable');
    final data=jsonDecode(response.body);
    final meta=data is Map?data['meta']:null;
    final rows=meta is Map?meta['videos']:null;
    if(rows is! List)return [];
    final result=<DesktopEpisode>[];
    for(final row in rows){
      if(row is! Map)continue;
      final season=row['season'],number=row['episode'];
      if(season is! int||number is! int||season<0||number<1)continue;
      result.add(DesktopEpisode(season,number,row['title']?.toString()??'Episode $number','$id:$season:$number'));
    }
    result.sort((a,b)=>a.season==b.season?a.number.compareTo(b.number):a.season.compareTo(b.season));
    return result;
  }
  @override void close()=>_client.close();
}
