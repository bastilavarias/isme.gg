import 'package:flutter/material.dart';
import 'design.dart';
import 'engine.dart';

/// One ordered homepage contract for every device. Weekly titles are conditional
/// on actual weekly metadata, never on the ordinary popular catalog.
const homeSectionKeys=['weekly_movies','weekly_tv','recent_home','pinoy_home','korean_home','anime'];
const weeklySectionKeys={'weekly_movies','weekly_tv','weekly_series','weekly_anime'};
Map<String,String> homeSections(Set<String> verifiedWeekly)=> {
  'weekly_movies':verifiedWeekly.contains('weekly_movies')?'Top 10 Movies This Week':'Trending movies',
  'weekly_tv':verifiedWeekly.contains('weekly_tv')?'Top 10 TV Shows This Week':'Popular series',
  'recent_home':'Recently Released',
  'pinoy_home':'Tatak Pinoy',
  'korean_home':'K-Drama Fever',
  'anime':'Anime Spotlight',
};
bool isRankedSection(String title)=>const {'Top 10 Movies This Week','Top 10 TV Shows This Week','Top 10 Anime This Week'}.contains(title);
List<Movie> sectionMovies(String key,CatalogSnapshot snapshot){
  final seen=<String>{};
  final ranked=weeklySectionKeys.contains(key)&&snapshot.source=='tmdb_weekly';
  return snapshot.movies.where((m)=>m.id.isNotEmpty&&seen.add(m.id)).take(ranked?10:30).toList();
}
void rememberWeekly(Set<String> verified,String key,CatalogSnapshot snapshot){
  if(!weeklySectionKeys.contains(key))return;
  if(snapshot.source=='tmdb_weekly'&&snapshot.movies.isNotEmpty){verified.add(key);}else{verified.remove(key);}
}
/// Deterministic daily featured selection; avoid changing an active TV cursor.
List<Movie> featuredToday(Iterable<Movie> candidates,{DateTime? now,int limit=4}){
  final seen=<String>{};
  final rows=candidates.where((m)=>m.art.isNotEmpty&&seen.add(m.id)).take(20).toList();
  if(rows.isEmpty)return [];
  final today=now??DateTime.now();
  final day=DateTime.utc(today.year,today.month,today.day).millisecondsSinceEpoch~/86400000;
  final start=day%rows.length;
  return [...rows.skip(start),...rows.take(start)].take(limit).toList();
}
String resumeTitle(Movie movie){
  if(!movie.isEpisode)return movie.title;
  final match=RegExp(r':s(\d+):e(\d+)$').firstMatch(movie.id);
  if(match==null)return movie.title;
  final suffix=' · S${match[1]} E${match[2]}';
  return movie.title.endsWith(suffix)?movie.title:'${movie.title}$suffix';
}

/// Oversized outlined rank beside poster, shared between TV and mobile.
class RankedArtwork extends StatelessWidget {
  final int rank;
  final Widget child;
  const RankedArtwork({super.key,required this.rank,required this.child});
  @override Widget build(BuildContext context)=>LayoutBuilder(builder:(ctx,box){
    final left=box.maxWidth*(rank==10 ? .42 : .34);
    final style=TextStyle(fontWeight:FontWeight.w900,fontSize:box.maxHeight*.68,height:1,letterSpacing:-5);
    return Stack(fit:StackFit.expand,children:[
      Positioned(left:left,right:0,top:0,bottom:0,child:ClipRRect(borderRadius:BorderRadius.circular(6),child:child)),
      Positioned(left:0,bottom:0,width:left+box.maxWidth*.12,height:box.maxHeight*.85,
        child:ExcludeSemantics(child:FittedBox(fit:BoxFit.contain,alignment:Alignment.bottomLeft,
          child:Stack(children:[
            Text('$rank',style:style.copyWith(foreground:Paint()..style=PaintingStyle.stroke..strokeWidth=3..color=CinemaColors.muted)),
            Text('$rank',style:style.copyWith(color:CinemaColors.canvas)),
          ])))),
    ]);
  });
}
