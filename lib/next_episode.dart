import 'engine.dart';

/// Stable playback, rather than a scrubber jump, enables speculative preparation.
/// The completion path deliberately does not depend on this gate.
class NextEpisodeGate {
  Duration? _position, _sampleTime;
  Duration stable=Duration.zero;
  void reset(){_position=null;_sampleTime=null;stable=Duration.zero;}
  bool sample({required Duration position,required Duration duration,
    required Duration now,required bool playing,required bool buffering}){
    final previous=_position,stamp=_sampleTime;
    _position=position;_sampleTime=now;
    if(!playing||buffering||duration<=Duration.zero||previous==null||stamp==null){
      stable=Duration.zero;return false;
    }
    final elapsed=now-stamp,advanced=position-previous;
    if(elapsed<=Duration.zero||elapsed>const Duration(seconds:4)||
        advanced<=Duration.zero||advanced>elapsed+const Duration(milliseconds:750)){
      stable=Duration.zero;return false;
    }
    stable+=elapsed;
    return position.inMilliseconds/duration.inMilliseconds>=.70&&stable>=const Duration(seconds:5);
  }
  static bool preview(Duration position,Duration duration)=>duration>Duration.zero&&
    position.inMilliseconds/duration.inMilliseconds>=.95;
}

class EpisodeIdentity {
  final String parentId;
  final int season,episode;
  const EpisodeIdentity(this.parentId,this.season,this.episode);
  static EpisodeIdentity? parse(Movie movie){
    if(!movie.isEpisode)return null;
    final m=RegExp(r'^(.*):s([0-9]{1,5}):e([0-9]{1,5})$').firstMatch(movie.id);
    if(m==null)return null;
    return EpisodeIdentity(m.group(1)!,int.parse(m.group(2)!),int.parse(m.group(3)!));
  }
  Movie parent(Movie movie)=>Movie(id:parentId,title:movie.title.replaceFirst(RegExp(r' · S[0-9]+ E[0-9]+$'),''),
    type:movie.type,poster:movie.poster,tmdbId:movie.tmdbId,pinoy:movie.pinoy,animeFilm:movie.animeFilm);
}

Movie episodeMovie(Movie show,int season,Episode episode)=>Movie(
  id:'${show.id}:s$season:e${episode.number}',
  title:'${show.title} · S$season E${episode.number}',type:show.type,
  poster:show.poster,backdrop:episode.thumbnail.isEmpty?show.art:episode.thumbnail,
  description:episode.description,episodeTitle:episode.title,tmdbId:show.tmdbId,pinoy:show.pinoy,animeFilm:show.animeFilm);

bool aired(Episode ep,DateTime now){
  final date=DateTime.tryParse(ep.airDate);
  if(date==null)return true; // Some otherwise available provider records omit dates.
  if(ep.airDate.length==10){
    return !date.isAfter(DateTime(now.year,now.month,now.day));
  }
  return !date.isAfter(now);
}

/// Preserve provider numbering; never guess an episode number. Specials are
/// browsable manually but do not interrupt the regular-season sequence.
Future<Movie?> findNextEpisode(NativeEngine engine,Movie current,{DateTime? now}) async {
  final id=EpisodeIdentity.parse(current);
  if(id==null)return null;
  final show=id.parent(current),today=now??DateTime.now();
  final currentSeason=await engine.episodes(show,id.season);
  for(final ep in currentSeason){
    if(ep.number>id.episode)return aired(ep,today)?episodeMovie(show,id.season,ep):null;
  }
  if(id.season==0)return null;
  final seasons=await engine.seasons(show);
  for(final season in seasons.where((s)=>s.number>id.season)){
    final episodes=await engine.episodes(show,season.number);
    if(episodes.isEmpty)continue;
    final ep=episodes.first;
    return aired(ep,today)?episodeMovie(show,season.number,ep):null;
  }
  return null;
}
