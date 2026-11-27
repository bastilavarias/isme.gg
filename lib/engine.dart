import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Only fall back to matching data, never recycle a generic catalog under a
/// specific date, genre, nationality, ranking or independent-film claim.
const editorialFallback={
  'weekly_movies':'trending','weekly_tv':'series','weekly_series':'series','weekly_anime':'anime',
  'pinoy_home':'pinoy','korean_home':'korean','recent_home':'',
  'page_movies_action':'action','page_movies_comedy':'comedy','page_movies_horror':'horror',
  'page_movies_scifi':'scifi','page_movies_romance':'romance','page_movies_rated':'top_rated',
  'page_series_crime':'series_crime','page_series_drama':'series_drama','page_series_comedy':'series_comedy',
  'page_series_rated':'series_rated',
  'page_pinoy_movies':'pinoy','page_pinoy_series':'series_pinoy','page_pinoy_classics':'pinoy',
};
bool editorialCollection(String key)=>key.startsWith('page_')||editorialFallback.containsKey(key);
List<Movie> editorialFallbackMovies(String key,List<Movie> movies){
  if(key=='weekly_series'||key.startsWith('page_series_'))return movies.where((m)=>m.type=='Series').toList();
  if(key=='weekly_anime'||key.startsWith('page_anime_'))return movies.where((m)=>m.type=='Anime'||m.animeFilm).toList();
  if(key=='page_pinoy_classics')return movies.where((m){final y=int.tryParse(m.year);return y!=null&&y>0&&y<2000;}).toList();
  return movies;
}

class Movie {
  final String id, title, description, poster, backdrop;
  final String year, genre, runtime, rating;
  final int tmdbId;
  final String type, episodeTitle;
  final bool pinoy,animeFilm;
  bool get episodic=>type=='Series'||type=='Anime';
  bool get isEpisode=>episodic&&RegExp(r'^(imdb:tt[0-9]{7,10}|tmdb:tv:[1-9][0-9]{0,8}):s[0-9]{1,5}:e[0-9]{1,5}$').hasMatch(id);
  const Movie({required this.id, required this.title, this.description = '', this.poster = '', this.backdrop = '', this.year = '', this.genre = '', this.runtime = '', this.rating = '', this.tmdbId = 0, this.type='Movie', this.episodeTitle='',this.pinoy=false,this.animeFilm=false});
  static String _field(dynamic value) => value == null ? '' : value.toString().trim();
  static String _genre(dynamic value) => value is List ? value.take(2).map(_field).where((s)=>s.isNotEmpty).join(', ') : _field(value);
  String get metadata => [type,genre,year,runtime,rating].where((s)=>s.isNotEmpty).join(' · ');
  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id']?.toString() ?? '', title: j['title']?.toString() ?? '',
    description: j['description']?.toString() ?? '', poster: j['poster']?.toString() ?? '',
    backdrop: _field(j['backdrop']), year: _field(j['year']), genre: _genre(j['genres']??j['genre']), runtime: _field(j['runtime']), rating: _field(j['ratingLabel']??j['rating']), tmdbId: int.tryParse(_field(j['tmdbId']))??0, type: const ['Series','Anime'].contains(j['type'])?j['type'] as String:'Movie', episodeTitle:_field(j['episodeTitle']),pinoy:j['pinoy']==true,animeFilm:j['animeFilm']==true);
  Map<String, dynamic> toJson() => {'id':id,'title':title,'description':description,'poster':poster,'backdrop':backdrop,'year':year,'genre':genre,'runtime':runtime,'ratingLabel':rating,'tmdbId':tmdbId,'type':type,'episodeTitle':episodeTitle,'pinoy':pinoy,'animeFilm':animeFilm};
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
  final String source;
  const CatalogSnapshot(this.movies,{required this.cacheHit,required this.stale,this.source=''});
  factory CatalogSnapshot.fromJson(Map<String,dynamic> data)=>CatalogSnapshot(
    (data['items'] as List? ?? []).whereType<Map<String,dynamic>>().map(Movie.fromJson)
      .where((m)=>m.id.isNotEmpty&&m.title.isNotEmpty).toList(),
    cacheHit:data['cacheHit']==true,stale:data['stale']==true,source:data['source']?.toString()??'');
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
  String appVersion='';
  int appVersionCode=0;
  bool isUpgrade=false;
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
    appVersion=result['versionName']?.toString()??'';
    appVersionCode=(result['versionCode'] as num?)?.toInt()??0;
    isUpgrade=result['isUpgrade']==true;
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
    if(editorialCollection(collection)){
      if(providersConfigured){
        try{
          final data=CatalogSnapshot.fromJson(await json('/api/home/catalog',body:{'collection':collection,'mode':mode,'token':_providerToken}));
          if(data.movies.isNotEmpty)return data;
        }catch(_){
          if(mode!='cached'&&collection.startsWith('page_')&&(editorialFallback[collection]??'').isEmpty)rethrow;
        }
      }
      final fallback=editorialFallback[collection]??'';
      if(fallback.isEmpty)return const CatalogSnapshot([],cacheHit:false,stale:false);
      final data=await catalogSnapshot(fallback,mode:mode);
      // Never advertise generic popular data as a verified weekly ranking.
      final items=editorialFallbackMovies(collection,data.movies);
      return CatalogSnapshot(items,cacheHit:data.cacheHit,stale:providersConfigured||data.stale,source:'fallback');
    }
    final CatalogSnapshot data;
    if(collection.startsWith('series')||collection.startsWith('anime')){
      data=CatalogSnapshot.fromJson(await json('/api/tv/catalog',body:{
        'collection':collection,'query':query,'mode':mode,'token':_providerToken}));
    }else{
      data=CatalogSnapshot.fromJson(await json('/api/catalog',query:{'collection':collection,'query':query,'mode':mode}));
    }
    if(query.isEmpty&&(collection=='pinoy'||collection=='series_pinoy')){
      return CatalogSnapshot(data.movies.map((m)=>Movie.fromJson({...m.toJson(),'pinoy':true})).toList(),
        cacheHit:data.cacheHit,stale:data.stale,source:data.source);
    }
    return data;
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
  Future<void> start(Movie movie, {String magnet = '', int source = 0, bool fastStartup = false, bool adaptiveBuffering = false}) async {
    await json('/api/play',body:{'id':movie.id,'title':movie.title,'magnet':magnet,'sourceIndex':source,if(fastStartup)'fastStartup':true,if(adaptiveBuffering)'adaptiveBuffering':true,if(movie.isEpisode&&movie.id.startsWith('tmdb:tv:'))'tmdbToken':_providerToken});
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
  Future<void> updateDirectBuffer(String uri,bool urgent) async {
    await channel.invokeMethod<void>('updateDirectBuffer',{'uri':uri,'urgent':urgent});
  }
  Future<void> finishDirectStartup(String uri) async {
    await channel.invokeMethod<void>('finishDirectStartup',{'uri':uri});
  }
  Future<void> cancelDirectReads(String uri) async {
    await channel.invokeMethod<void>('cancelDirectReads',{'uri':uri});
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
  Future<void> setSupportUiActive(bool active) async {
    try{await channel.invokeMethod<void>('setSupportUiActive',{'active':active});}catch(_){}
  }
  Future<void> openIssueReport()=>channel.invokeMethod<void>('openIssueReport');
  Future<void> clearCatalogCache() async {
    await SqliteLibraryPersistence.channel.invokeMethod<void>('clearCatalogCache');
    _providerMemo.clear();providerRevision.value++;
  }
  Future<bool> clearLocalData() async=>await channel.invokeMethod<bool>('clearLocalData')??false;
  Future<void> setPlaybackScreenOn(bool active) async {
    try{await channel.invokeMethod<void>('setPlaybackScreenOn',{'active':active});}catch(_){}
  }
  Future<void> setPlaybackActive(bool active) async {
    try{await channel.invokeMethod<void>('setPlaybackActive',{'active':active});}catch(_){}
  }
  void dispose(){_disposed=true;_providerMemo.clear();_client.close();providerRevision.dispose();}
}
/// Production library persistence is native SQLite. The memory implementation
/// is explicitly injected by tests; it is never a fallback for database errors.
abstract class LibraryPersistence {
  Future<Map<String,dynamic>> open(String bookmarks,String history);
  Future<List<Map<String,dynamic>>> readBookmarks();
  Future<void> writeBookmark(String id,Map<String,dynamic>? row);
  Future<void> writeHistory(String id,Map<String,dynamic>? row);
  Future<void> clearHistory();
}
class SqliteLibraryPersistence implements LibraryPersistence {
  static const channel=MethodChannel('gg.isme/library');
  @override Future<Map<String,dynamic>> open(String bookmarks,String history) async {
    final raw=await channel.invokeMethod<String>('open',{'bookmarks':bookmarks,'history':history});
    if(raw==null)throw StateError('Local library unavailable');
    return Map<String,dynamic>.from(jsonDecode(raw) as Map);
  }
  @override Future<List<Map<String,dynamic>>> readBookmarks() async{
    final raw=await channel.invokeMethod<String>('readBookmarks');
    if(raw==null)throw StateError('Local bookmarks unavailable');
    return (jsonDecode(raw) as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
  }
  @override Future<void> writeBookmark(String id,Map<String,dynamic>? row)=>channel.invokeMethod<void>(
    'bookmark',{'id':id,'payload':row==null?null:jsonEncode(row)});
  @override Future<void> clearHistory()=>channel.invokeMethod<void>('clearHistory');
  @override Future<void> writeHistory(String id,Map<String,dynamic>? row)=>channel.invokeMethod<void>(
    'history',{'id':id,'payload':row==null?null:jsonEncode(row)});
}

/// Test-only persistence, injectable without Android plugins.
class MemoryLibraryPersistence implements LibraryPersistence {
  final bookmarks=<String,Map<String,dynamic>>{},history=<String,Map<String,dynamic>>{};
  bool migrated=false;
  @override Future<Map<String,dynamic>> open(String saved,String watched) async{
    if(!migrated){
      for(final row in (jsonDecode(saved) as List).whereType<Map<String,dynamic>>()){
        bookmarks.putIfAbsent(row['id'] as String,()=>row);
      }
      for(final row in (jsonDecode(watched) as Map).values.whereType<Map<String,dynamic>>()){
        history.putIfAbsent(row['id'] as String,()=>row);
      }
      migrated=true;
    }
    final savedRows=bookmarks.values.toList()..sort((a,b)=>(b['addedAt'] as int).compareTo(a['addedAt'] as int));
    final watchedRows=history.values.toList()..sort((a,b)=>(b['updated'] as int).compareTo(a['updated'] as int));
    return {'bookmarks':savedRows,'history':watchedRows};
  }
  @override Future<List<Map<String,dynamic>>> readBookmarks() async=>bookmarks.values.toList()
    ..sort((a,b)=>(b['addedAt'] as int).compareTo(a['addedAt'] as int));
  @override Future<void> writeBookmark(String id,Map<String,dynamic>? row) async{
    if(row==null){bookmarks.remove(id);}else{bookmarks[id]=row;}
  }
  @override Future<void> clearHistory() async{history.clear();}
  @override Future<void> writeHistory(String id,Map<String,dynamic>? row) async{
    if(row==null){history.remove(id);}else{history[id]=row;}
    final sorted=history.values.toList()..sort((a,b)=>(b['updated'] as int).compareTo(a['updated'] as int));
    for(final item in sorted.skip(30)){history.remove(item['id']);}
  }
}

class History {
  final SharedPreferences prefs;
  final LibraryPersistence _storage;
  final Map<String,Map<String,dynamic>> _data;
  final BookmarkStore bookmarks;
  Future<void> _queue=Future.value();

  History._(this.prefs,this._storage,this._data,this.bookmarks);
  /// Existing widget tests can use an explicitly in-memory library.
  factory History.inMemory(SharedPreferences prefs){
    final storage=MemoryLibraryPersistence();
    return History._(prefs,storage,{},BookmarkStore(storage,[]));
  }

  static Future<History> open(SharedPreferences prefs,{LibraryPersistence? persistence}) async {
    final storage=persistence??SqliteLibraryPersistence();
    // Keep malformed legacy values untouched for recovery. Only remove a
    // successfully parsed and committed legacy value after SQLite responds.
    final oldBookmarks=prefs.getString('bookmarks-v1');
    final oldHistory=prefs.getString('watch-v1');
    var bookmarkValid=true,historyValid=true;
    final saved=<Map<String,dynamic>>[],watched=<String,Map<String,dynamic>>{};
    try{
      for(final raw in jsonDecode(oldBookmarks??'[]') as List){
        final row=Map<String,dynamic>.from(raw as Map);
        final movie=BookmarkStore.parent(Movie.fromJson(row));
        if(!BookmarkStore.valid(movie)||movie.title.isEmpty){bookmarkValid=false;continue;}
        if(!saved.any((r)=>BookmarkStore.same(Movie.fromJson(r),movie))){
          saved.add({...movie.toJson(),'addedAt':row['addedAt'] is int?row['addedAt']:0});
        }
      }
    }catch(_){bookmarkValid=false;}
    try{
      for(final raw in (jsonDecode(oldHistory??'{}') as Map).values){
        final row=Map<String,dynamic>.from(raw as Map);
        final movie=Movie.fromJson(row);
        if(movie.id.isEmpty||movie.title.isEmpty||row['time'] is! int||row['duration'] is! int||row['updated'] is! int||
          (row['time'] as int)<0||(row['duration'] as int)<0){historyValid=false;continue;}
        watched[movie.id]=row;
      }
    }catch(_){historyValid=false;}
    final snapshot=await storage.open(jsonEncode(saved),jsonEncode(watched));
    final data=<String,Map<String,dynamic>>{};
    for(final raw in snapshot['history'] as List){
      final row=Map<String,dynamic>.from(raw as Map);
      data[row['id'] as String]=row;
    }
    final store=BookmarkStore(storage,(snapshot['bookmarks'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList());
    if(bookmarkValid&&oldBookmarks!=null)await prefs.remove('bookmarks-v1');
    if(historyValid&&oldHistory!=null)await prefs.remove('watch-v1');
    return History._(prefs,storage,data,store);
  }

  List<Movie> movies() {
    final rows = _data.values.toList()
      ..sort((a,b)=>(b['updated'] as int).compareTo(a['updated'] as int));
    return rows.map(Movie.fromJson).toList();
  }
  Duration position(Movie m) => Duration(seconds: (_data[m.id]?['time'] as int?) ?? 0);
  double? fraction(Movie m){
    final row=_data[m.id],time=row?['time'],duration=row?['duration'];
    return time is num&&duration is num&&duration>0?(time/duration).clamp(0.0,1.0).toDouble():null;
  }
  Future<void> clear() {
    final job=_queue.then((_)async{await _storage.clearHistory();_data.clear();await prefs.remove('watch-v1');});
    _queue=job.then<void>((_){},onError:(Object _,StackTrace __){});
    return job;
  }
  Future<void> save(Movie m, Duration position, Duration duration) {
    final seconds=position.inSeconds;
    if(seconds<12 || m.id.isEmpty || duration.isNegative)return Future.value();
    final job=_queue.then((_)async{
      final completed=duration.inSeconds>0&&seconds/duration.inSeconds>0.97;
      final row=completed?null:<String,dynamic>{...m.toJson(),'time':seconds,'duration':duration.inSeconds,'updated':DateTime.now().millisecondsSinceEpoch};
      await _storage.writeHistory(m.id,row);
      if(row==null){_data.remove(m.id);}else{_data.remove(m.id);_data[m.id]=row;}
      final entries=_data.entries.toList().reversed.toList()..sort((a,b)=>(b.value['updated'] as int).compareTo(a.value['updated'] as int));
      for(final entry in entries.skip(30)){_data.remove(entry.key);}
    });
    _queue=job.then<void>((_){},onError:(Object _,StackTrace __){});
    return job;
  }
}

/// Saved titles are independent of watch progress and stay on this device.
class BookmarkStore extends ChangeNotifier {
  final LibraryPersistence _storage;
  final List<Movie> _items=[];
  int _lastAddedAt=0;
  Future<void> _queue=Future.value();
  BookmarkStore(this._storage,List<Map<String,dynamic>> rows){_replace(rows);}
  void _replace(List<Map<String,dynamic>> rows){
    _items.clear();
    for(final row in rows){
      final item=parent(Movie.fromJson(row));
      if(valid(item)&&item.title.isNotEmpty&&!contains(item))_items.add(item);
      final added=row['addedAt'];
      if(added is int&&added>_lastAddedAt)_lastAddedAt=added;
    }
  }

  static Movie parent(Movie movie){
    if(!movie.isEpisode)return movie;
    return Movie(id:movie.id.replaceFirst(RegExp(r':s[0-9]+:e[0-9]+$'),''),
      title:movie.title.replaceFirst(RegExp(r' · S[0-9]+ E[0-9]+$'),''),
      poster:movie.poster,type:movie.type,tmdbId:movie.tmdbId,
      pinoy:movie.pinoy,animeFilm:movie.animeFilm);
  }
  static int tmdb(Movie movie)=>movie.tmdbId>0?movie.tmdbId:
    movie.id.startsWith('tmdb:')?(int.tryParse(movie.id.split(':').last)??0):0;
  static bool same(Movie a,Movie b){
    final x=parent(a),y=parent(b);
    if(x.episodic!=y.episodic)return false;
    return (x.id.isNotEmpty&&x.id==y.id)||(tmdb(x)>0&&tmdb(x)==tmdb(y));
  }
  static bool valid(Movie movie)=>RegExp(r'^(imdb:tt[0-9]{7,10}|tmdb:(movie|tv):[1-9][0-9]{0,8})$').hasMatch(movie.id);
  List<Movie> get movies=>List.unmodifiable(_items);
  bool contains(Movie movie)=>_items.any((m)=>same(m,movie));
  Future<void> refresh(){
    final job=_queue.then((_)async{
      _replace(await _storage.readBookmarks());
      notifyListeners();
    });
    _queue=job.then<void>((_){},onError:(Object _,StackTrace __){});
    return job;
  }
  Future<void> toggle(Movie movie)=>_change(movie,null);
  Future<void> remove(Movie movie)=>_change(movie,false);
  Future<void> _change(Movie movie,bool? save){
    final item=parent(movie);
    final job=_queue.then((_) async{
      if(!valid(item)||item.title.isEmpty)throw ArgumentError('Invalid saved title');
      final existing=_items.where((m)=>same(m,item)).firstOrNull;
      final exists=existing!=null,wanted=save??!exists;
      if(exists==wanted)return;
      if(wanted){
        final now=DateTime.now().millisecondsSinceEpoch;
        final addedAt=now>_lastAddedAt?now:_lastAddedAt+1;
        await _storage.writeBookmark(item.id,{...item.toJson(),'addedAt':addedAt});
        _lastAddedAt=addedAt;
        _items.insert(0,item);
      }else{
        await _storage.writeBookmark(existing!.id,null);
        _items.removeWhere((m)=>same(m,item));
      }
      notifyListeners();
    });
    _queue=job.then<void>((_){},onError:(Object _,StackTrace __){});
    return job;
  }
}
