import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Movie {
  final String id, title, description, poster, backdrop;
  final String year, genre, runtime, rating;
  const Movie({required this.id, required this.title, this.description = '', this.poster = '', this.backdrop = '', this.year = '', this.genre = '', this.runtime = '', this.rating = ''});
  static String _field(dynamic value) => value == null ? '' : value.toString().trim();
  static String _genre(dynamic value) => value is List ? value.take(2).map(_field).where((s)=>s.isNotEmpty).join(', ') : _field(value);
  String get metadata => ['Movie',genre,year,runtime,rating].where((s)=>s.isNotEmpty).join(' · ');
  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
    id: j['id']?.toString() ?? '', title: j['title']?.toString() ?? '',
    description: j['description']?.toString() ?? '', poster: j['poster']?.toString() ?? '',
    backdrop: _field(j['backdrop']), year: _field(j['year']), genre: _genre(j['genres']??j['genre']), runtime: _field(j['runtime']), rating: _field(j['ratingLabel']));
  Map<String, dynamic> toJson() => {'id':id,'title':title,'description':description,'poster':poster,'backdrop':backdrop,'year':year,'genre':genre,'runtime':runtime,'ratingLabel':rating};
  String get art => backdrop.isNotEmpty ? backdrop : poster;
}
class NativeEngine {
  static const channel = MethodChannel('gg.isme/native');
  final http.Client _client = http.Client();
  late final Uri origin;
  late final String token;
  bool tv = false;
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
  Future<List<Movie>> catalog(String collection, {String query = ''}) async {
    final data = await json('/api/catalog', query: {'collection':collection,'query':query});
    return (data['items'] as List? ?? []).whereType<Map<String,dynamic>>().map(Movie.fromJson).where((m)=>m.id.isNotEmpty && m.title.isNotEmpty).toList();
  }
  Future<void> start(Movie movie, {String magnet = '', int source = 0}) async {
    await json('/api/play',body:{'id':movie.id,'title':movie.title,'magnet':magnet,'sourceIndex':source});
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
  void dispose() => _client.close();
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
