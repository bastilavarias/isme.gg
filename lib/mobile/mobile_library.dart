import 'dart:convert';
import '../engine.dart';

/// Local-only bookmarks. Existing watch-v1 records remain compatible with TV.
class MobileLibrary {
  final History history;
  MobileLibrary(this.history);
  Map<String,Movie> get saved {
    try{
      final rows=jsonDecode(history.prefs.getString('isme-mobile-list-v1')??'[]') as List;
      return {for(final row in rows.whereType<Map<String,dynamic>>())
        if(Movie.fromJson(row).id.isNotEmpty)Movie.fromJson(row).id:Movie.fromJson(row)};
    }catch(_){return {};}
  }
  bool contains(Movie movie)=>saved.containsKey(movie.id);
  Future<void> toggle(Movie movie) async{
    final items=saved;
    if(items.containsKey(movie.id)){items.remove(movie.id);}
    else{items[movie.id]=movie;}
    await history.prefs.setString('isme-mobile-list-v1',jsonEncode(items.values.take(200).map((m)=>m.toJson()).toList()));
  }
  List<Movie> get recent=>history.movies();
  Movie? resumeFor(Movie show){
    for(final m in recent){
      if(m.id==show.id||m.id.startsWith('${show.id}:s'))return m;
    }
    return null;
  }
  double? fraction(Movie movie){
    // Older history entries contain only elapsed time, so never invent a percentage.
    try{
      final row=(jsonDecode(history.prefs.getString('watch-v1')??'{}') as Map)[movie.id];
      final time=row?['time'],duration=row?['duration'];
      if(time is num&&duration is num&&duration>0)return (time/duration).clamp(0.0,1.0).toDouble();
    }catch(_){}
    return null;
  }
}
