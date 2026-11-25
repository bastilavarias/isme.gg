import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Movie {
  final String id, title, description, poster, backdrop;
  final String year, genre, runtime, rating;
  final int tmdbId;
  final String type, episodeTitle;
  bool get episodic=>type=='Series'||type=='Anime';
  bool get isEpisode=>episodic&&RegExp(r'^(imdb:tt[0-9]{7,10}|tmdb:tv:[1-9][0-9]{0,8}):s[0-9]{1,5}:e[0-9]{1,5}$').hasMatch(id);
  const Movie({required this.id, required this.title, this.description = '', this.poster = '', this.backdrop = '', this.year = '', this.genre = '', this.runtime = '', this.rating = '', this.tmdbId = 0, this.type='Movie', this.episodeTitle=''});
  static String _field(dynamic value) => value == null ? '' : value.toString().trim();
  static String _genre(dynamic value) => value is List ? value.take(2).map(_field).where((s)=>s.isNotEmpty).join(', ') : _field(value);
  String get metadata => [type,genre,year,runtime,rating].where((s)=>s.isNotEmpty).join(' · ');
  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id']?.toString() ?? '', title: j['title']?.toString() ?? '',
    description: j['description']?.toString() ?? '', poster: j['poster']?.toString() ?? '',
    backdrop: _field(j['backdrop']), year: _field(j['year']), genre: _genre(j['genres']??j['genre']), runtime: _field(j['runtime']), rating: _field(j['ratingLabel']), tmdbId: int.tryParse(_field(j['tmdbId']))??0, type: const ['Series','Anime'].contains(j['type'])?j['type'] as String:'Movie', episodeTitle:_field(j['episodeTitle']));
  Map<String, dynamic> toJson() => {'id':id,'title':title,'description':description,'poster':poster,'backdrop':backdrop,'year':year,'genre':genre,'runtime':runtime,'ratingLabel':rating,'tmdbId':tmdbId,'type':type,'episodeTitle':episodeTitle};
  String get art => backdrop.isNotEmpty ? backdrop : poster;
}
class Season {
  final int number;
  final String name;
  const Season(this.number,this.name);
}
class Episode {
  final int number;
  final String title,description,thumbnail,airDate;
  final int runtime;
  const Episode({required this.number,required this.title,this.description='',this.thumbnail='',this.airDate='',this.runtime=0});
  factory Episode.fromJson(Map<String,dynamic> j)=>Episode(number:(j['number'] as num?)?.toInt()??0,
    title:j['title']?.toString()??'',description:j['description']?.toString()??'',thumbnail:j['thumbnail']?.toString()??'',
    airDate:j['airDate']?.toString()??'',runtime:(j['runtime'] as num?)?.toInt()??0);
}
class CatalogSnapshot {
  final List<Movie> movies;
  final bool cacheHit, stale;
  const CatalogSnapshot(this.movies,{required this.cacheHit,required this.stale});
  factory CatalogSnapshot.fromJson(Map<String,dynamic> data)=>CatalogSnapshot(
    (data['items'] as List? ?? []).whereType<Map<String,dynamic>>().map(Movie.fromJson)
      .where((m)=>m.id.isNotEmpty&&m.title.isNotEmpty).toList(),
    cacheHit:data['cacheHit']==true,stale:data['stale']==true);
}
class WatchProvider {
  final int id;
  final String name,logo;
  final bool movie,tv;
  const WatchProvider({required this.id,required this.name,this.logo='',this.movie=false,this.tv=false});
  factory WatchProvider.fromJson(Map<String,dynamic> j)=>WatchProvider(
    id:(j['id'] as num?)?.toInt()??0,name:j['name']?.toString()??'',logo:j['logo']?.toString()??'',
    movie:j['movie']==true,tv:j['tv']==true);
}
class NativeEngine {
  static const channel = MethodChannel('gg.isme/native');
  final http.Client _client = http.Client();
  late final Uri origin;
  late final String token;
  bool tv = false;
  String providerCountry='PH';
  String _providerToken='';
  final providerRevision=ValueNotifier<int>(0);
  final _providerMemo=<String,({Future<String?> value,DateTime until})>{};
  final _providerLanes=<Future<void>>[Future.value(),Future.value()];
  int _providerLane=0;
  bool _disposed=false, _providerBlocked=false;
  bool get providersConfigured=>_providerToken.isNotEmpty;
  Future<void> restoreMetadataCredential() async {
    try{_providerToken=(await channel.invokeMethod<String>('readMetadataCredential')??'').trim();}catch(_){}
  }
  Future<void> rememberMetadataCredential(String token) async {
    await channel.invokeMethod<void>('saveMetadataCredential',{'token':token.trim()});
  }
  Future<void> configureMetadata(String country,String? token) async {
    final value=token??_providerToken;
    configureProviders(country,value);
    if(token!=null)await rememberMetadataCredential(value);
  }
  void configureProviders(String country,String token){
    providerCountry=country.toUpperCase();
    _providerToken=token.trim();
    _providerBlocked=false;
    _providerMemo.clear();
    providerRevision.value++;
  }
  Future<String?> providerFor(Movie movie){
    if(_disposed||!(RegExp(r'^imdb:tt[0-9]{7,10}$').hasMatch(movie.id)||(movie.tmdbId>0&&(movie.id.startsWith('tmdb:tv:')||movie.id.startsWith('tmdb:movie:')))))return Future.value(null);
    final old=_providerMemo[movie.id];
    if(old!=null&&DateTime.now().isBefore(old.until))return old.value;
    final revision=providerRevision.value, country=providerCountry, token=_providerToken;
    final lane=_providerLane++%_providerLanes.length;
    final result=_providerLanes[lane].then<String?>((_)async{
      if(_disposed||revision!=providerRevision.value)return null;
      try{
        final data=await json('/api/providers',body:{
          'imdb':movie.id.startsWith('imdb:')?movie.id.substring(5):'','tmdbId':movie.tmdbId,'country':country,'tv':movie.episodic,
          'token':_providerBlocked?'':token,
        });
        if(_disposed||revision!=providerRevision.value)return null;
        final name=data['provider']?.toString().trim()??'';
        return name.isEmpty?null:name;
      }catch(e){
        if(!_disposed&&revision==providerRevision.value){
          if(RegExp(r'HTTP (401|403|429)').hasMatch(e.toString()))_providerBlocked=true;
        }
        return null;
      }
    });
    _providerLanes[lane]=result.then<void>((_){});
    _providerMemo[movie.id]=(value:result,until:DateTime.now().add(const Duration(minutes:15)));
    if(_providerMemo.length>300)_providerMemo.remove(_providerMemo.keys.first);
    return result;
  }
  Map<String,String> get headers => {'x-isme-token': token};
  Future<void> connect() async {
    final result = await channel.invokeMapMethod<String,dynamic>('connect');
    if (result == null) throw StateError('Native engine unavailable');
    origin = Uri.parse(result['origin'] as String);
    if (origin.host != '127.0.0.1' || origin.scheme != 'http') throw StateError('Invalid local origin');
    token = result['token'] as String; tv = result['tv'] == true;
  }
  Uri url(String path, [Map<String,String>? query]) => origin.resolve(path).replace(queryParameters: query);
  Future<Map<String,dynamic>> json(String path, {Map<String,String>? query, Map<String,dynamic>? body}) async {
    final uri = url(path, query);
    final res = await (body == null ? _client.get(uri, headers: headers) :
      _client.post(uri, headers: {...headers,'content-type':'application/json'}, body: jsonEncode(body)))
      .timeout(const Duration(seconds: 35));
    final data = jsonDecode(res.body) as Map<String,dynamic>;
    if (res.statusCode >= 400) throw StateError(data['error']?.toString() ?? 'Request failed');
    return data;
  }
  Future<CatalogSnapshot> catalogSnapshot(String collection,{String mode='normal',String query=''}) async {
    if(collection.startsWith('series')||collection.startsWith('anime')){
      return CatalogSnapshot.fromJson(await json('/api/tv/catalog',body:{
        'collection':collection,'query':query,'mode':mode,'token':_providerToken}));
    }
    return CatalogSnapshot.fromJson(await json('/api/catalog',query:{'collection':collection,'query':query,'mode':mode}));
  }
  Future<List<WatchProvider>> watchPlatforms({String mode='normal',bool artworkOnly=false}) async {
    final data=await json('/api/platforms',body:{'country':artworkOnly?'GLOBAL':providerCountry,'token':_providerToken,'mode':mode});
    return (data['providers'] as List? ?? []).whereType<Map<String,dynamic>>().map(WatchProvider.fromJson)
      .where((p)=>p.id>0&&p.name.isNotEmpty).toList();
  }
  Future<CatalogSnapshot> platformCatalog(List<int> ids,String kind,String row,{String mode='normal'}) async {
    if(ids.isEmpty)return const CatalogSnapshot([],cacheHit:false,stale:false);
    final sorted=ids.toSet().toList()..sort();
    return CatalogSnapshot.fromJson(await json('/api/platform/catalog',body:{
      'country':providerCountry,'token':_providerToken,'ids':sorted.join('|'),'kind':kind,'row':row,'mode':mode}));
  }
  Future<Movie> identifyMovie(Movie movie) async {
    if(movie.episodic||!movie.id.startsWith('tmdb:movie:'))return movie;
    final data=await json('/api/platform/movie-id',body:{'tmdbId':movie.tmdbId,'token':_providerToken});
    final imdb=data['imdb']?.toString()??'';
    if(!RegExp(r'^tt[0-9]{7,10}$').hasMatch(imdb))throw StateError('Movie identity unavailable');
    return Movie.fromJson({...movie.toJson(),'id':'imdb:$imdb'});
  }
  Future<List<Season>> seasons(Movie show) async {
    final data=await json('/api/tv/seasons',body:{'id':show.id,'token':_providerToken});
    final rows=(data['seasons'] as List? ?? []).whereType<Map<String,dynamic>>();
    final seen=<int>{};
    final result=rows.where((j)=>j['number'] is int&&(j['number'] as int)>=0&&seen.add(j['number'] as int))
      .map((j)=>Season(j['number'] as int,j['name']?.toString()??'')).toList();
    result.sort((a,b)=>a.number.compareTo(b.number));return result;
  }
  Future<List<Episode>> episodes(Movie show,int season) async {
    final data=await json('/api/tv/episodes',body:{'id':show.id,'season':season,'token':_providerToken});
    final seen=<int>{};
    final result=(data['episodes'] as List? ?? []).whereType<Map<String,dynamic>>().map(Episode.fromJson)
      .where((e)=>e.number>=0&&seen.add(e.number)).toList();
    result.sort((a,b)=>a.number.compareTo(b.number));return result;
  }
  Future<List<Movie>> catalog(String collection, {String query = ''}) async =>
    (await catalogSnapshot(collection,query:query)).movies;
  Future<void> start(Movie movie, {String magnet = '', int source = 0}) async {
    await json('/api/play',body:{'id':movie.id,'title':movie.title,'magnet':magnet,'sourceIndex':source,if(movie.isEpisode&&movie.id.startsWith('tmdb:tv:'))'tmdbToken':_providerToken});
  }
  Future<void> prepareNext(Movie current,Movie next) async {
    if(!current.isEpisode||!next.isEpisode)return;
    await json('/api/next/prepare',body:{'currentId':current.id,'id':next.id,'title':next.title,
      if(next.id.startsWith('tmdb:tv:'))'tmdbToken':_providerToken});
  }
  Future<void> cancelNext(Movie current) async {
    if(current.isEpisode)await json('/api/next/cancel',body:{'currentId':current.id});
  }
  Future<Map<String,dynamic>> status() => json('/api/status');
  // Validate bounded byte-range responses before handing the URI to Media3.
  Future<void> probe(Uri uri) async {
    if (uri.scheme != 'http' || uri.host != origin.host || uri.port != origin.port) {
      throw StateError('Invalid playback origin');
    }
    final request = http.Request('GET', uri)
      ..headers.addAll({...headers, 'Range': 'bytes=0-4095'});
    final response = await _client.send(request).timeout(const Duration(seconds: 40));
    final range = RegExp(r'^bytes 0-(\d+)/(\d+)$').firstMatch(response.headers['content-range'] ?? '');
    final end = range == null ? -1 : int.parse(range.group(1)!);
    final size = range == null ? 0 : int.parse(range.group(2)!);
    if (response.statusCode != 206 || size <= 0 ||
        end != (size < 4096 ? size - 1 : 4095) ||
        response.contentLength != end + 1) {
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
      throw StateError('Media range response invalid (HTTP ${response.statusCode})');
    }
    int received = 0;
    await for (final chunk in response.stream.timeout(const Duration(seconds: 40))) {
      received += chunk.length;
      if (received > end + 1) throw StateError('Media range response too long');
    }
    if (received != end + 1) throw StateError('Media range response truncated');
  }
  Future<Map<String,dynamic>> audioDiagnostics() async =>
    await channel.invokeMapMethod<String,dynamic>('audioDiagnostics') ?? {};
  Future<void> stop() async { await json('/api/stop',body:{}); }
  Future<List<Map<String,dynamic>>> subtitles() async {
    final data=await json('/api/subtitles');
    return (data['tracks'] as List? ?? []).whereType<Map<String,dynamic>>().toList();
  }
  Future<String> caption(int id) async {
    final res=await _client.get(url('/api/subtitle',{'id':'$id'}),headers:headers).timeout(const Duration(seconds:35));
    if(res.statusCode!=200) throw StateError('Subtitle unavailable');
    return utf8.decode(res.bodyBytes);
  }
  Future<void> checkUpdates() => channel.invokeMethod<void>('checkUpdates');
  void dispose(){_disposed=true;_providerMemo.clear();_client.close();providerRevision.dispose();}
}
class History {
  final SharedPreferences prefs;
  History(this.prefs);
  Map<String,dynamic> get _data {
    try { return Map<String,dynamic>.from(jsonDecode(prefs.getString('watch-v1') ?? '{}') as Map); } catch (_) { return {}; }
  }
  List<Movie> movies() {
    final rows = _data.values.whereType<Map<String,dynamic>>().toList()
      ..sort((a,b)=>(b['updated'] as int).compareTo(a['updated'] as int));
    return rows.map(Movie.fromJson).toList();
  }
  Duration position(Movie m) => Duration(seconds: (_data[m.id]?['time'] as int?) ?? 0);
  Future<void> save(Movie m, Duration position, Duration duration) async {
    final seconds=position.inSeconds;
    if(seconds<12 || m.id.isEmpty) return;
    final data=_data;
    if(duration.inSeconds>0 && seconds/duration.inSeconds>0.97) { data.remove(m.id); }
    else { data[m.id]={...m.toJson(),'time':seconds,'updated':DateTime.now().millisecondsSinceEpoch}; }
    final entries=data.entries.toList()..sort((a,b)=>(b.value['updated'] as int).compareTo(a.value['updated'] as int));
    await prefs.setString('watch-v1',jsonEncode(Map.fromEntries(entries.take(30))));
  }
}
