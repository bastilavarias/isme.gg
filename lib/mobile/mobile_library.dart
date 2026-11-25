import 'dart:convert';
import '../engine.dart';

/// Read-only mobile presentation helpers over the shared TV watch history.
class MobileLibrary {
  final History history;
  MobileLibrary(this.history);
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
