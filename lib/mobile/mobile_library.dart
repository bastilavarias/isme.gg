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
  double? fraction(Movie movie)=>history.fraction(movie);
}
