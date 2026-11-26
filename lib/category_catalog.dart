import 'engine.dart';
import 'home_sections.dart';

/// The same catalog specification drives both device shells.
const categoryNames=['Home','Movies','TV Series','Anime','Pinoy'];
String categoryName(String value)=>value=='Series'?'TV Series':value;
Map<String,String> categorySections(String value,Set<String> weekly){
  String title(String key,String ranked,String fallback)=>weekly.contains(key)?ranked:fallback;
  return switch(categoryName(value)){
    'Movies'=>{
      'weekly_movies':title('weekly_movies','Top 10 Movies This Week','Trending movies'),
      'page_movies_recent':'Recently Released',
      'page_movies_action':'Action & Adventure',
      'page_movies_comedy':'Comedy Movies',
      'page_movies_horror':'Horror & Thriller',
      'page_movies_scifi':'Science Fiction',
      'page_movies_romance':'Romance',
      'page_movies_rated':'Highly Rated Movies',
      'page_movies_gems':'Hidden Gems',
      'page_movies_classics':'Classic Movies',
    },
    'TV Series'=>{
      'weekly_series':title('weekly_series','Top 10 TV Shows This Week','Popular series'),
      'page_series_recent':'Recently Premiered',
      'page_series_airing':'Currently Airing',
      'page_series_binge':'Binge-worthy Series',
      'page_series_crime':'Crime & Mystery',
      'page_series_drama':'Drama Series',
      'page_series_comedy':'Comedy Series',
      'page_series_korean':'Korean Dramas',
      'page_series_rated':'Highly Rated Series',
    },
    'Anime'=>{
      'weekly_anime':title('weekly_anime','Top 10 Anime This Week','Popular anime'),
      'page_anime_airing':'Currently Airing',
      'page_anime_recent':'Recently Premiered',
      'page_anime_action':'Action & Adventure',
      'page_anime_fantasy':'Fantasy & Sci-Fi',
      'page_anime_romance':'Romance & Slice of Life',
      'page_anime_movies':'Anime Movies',
      'page_anime_rated':'All-Time Favorites',
    },
    'Pinoy'=>{
      'page_pinoy_movies':'Popular Pinoy Movies',
      'page_pinoy_series':'Popular Filipino Series',
      'page_pinoy_recent':'Bagong Pelikula',
      'page_pinoy_romance':'Pinoy Romance',
      'page_pinoy_comedy':'Pinoy Comedy',
      'page_pinoy_action':'Pinoy Action',
      'page_pinoy_horror':'Pinoy Horror',
      'page_pinoy_indie':'Independent Cinema',
      'page_pinoy_classics':'Pinoy Classics',
    },
    _=>homeSections(weekly),
  };
}
String categoryFeature(String value)=>switch(categoryName(value)){
  'Movies'=>'FEATURED MOVIE','TV Series'=>'FEATURED SERIES','Anime'=>'FEATURED ANIME','Pinoy'=>'FEATURED PINOY TITLE',_=>'FEATURED TODAY',
};

/// Some older history rows predate classification. Match known IDs or TMDB IDs
/// of the right media kind when possible, never guess nationality from a title.
bool belongsToCategory(Movie movie,String value,Iterable<Movie> known){
  switch(categoryName(value)){
    case 'Home':return true;
    case 'Movies':return !movie.episodic;
    case 'TV Series':return movie.type=='Series';
    case 'Anime':return movie.type=='Anime'||movie.animeFilm||known.any((m)=>m.animeFilm&&sameMedia(movie,m));
    case 'Pinoy':return movie.pinoy||known.any((m)=>m.pinoy&&sameMedia(movie,m));
    default:return false;
  }
}
bool sameMedia(Movie a,Movie b){
  if(a.episodic!=b.episodic)return false;
  final parent=a.id.replaceFirst(RegExp(r':s\d+:e\d+$'),'');
  return parent==b.id.replaceFirst(RegExp(r':s\d+:e\d+$'),'')||
    (a.tmdbId>0&&a.tmdbId==b.tmdbId);
}
