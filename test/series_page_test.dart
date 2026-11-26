import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/series_page.dart';
import 'package:ismegg/design.dart';

class SeriesEngine extends NativeEngine {
  SeriesEngine(){tv=true;}
  @override Future<List<Season>> seasons(Movie show) async=>const [Season(0,'Specials'),Season(1,'Season 1'),Season(2,'Season 2')];
  @override Future<List<Episode>> episodes(Movie show,int season) async=>[
    Episode(number:1,title:'Season $season first',description:'First episode',runtime:24),
    Episode(number:2,title:'Season $season second',description:'Second episode',runtime:25),
  ];
}
void main(){
  test('placeholder episode titles are not repeated',(){
    expect(distinctEpisodeTitle(const Episode(number:1,title:'Episode 1')),isEmpty);
    expect(distinctEpisodeTitle(const Episode(number:2,title:' EP. 2 ')),isEmpty);
    expect(distinctEpisodeTitle(const Episode(number:3,title:'Pilot')), 'Pilot');
  });
  testWidgets('episode release date includes month name and year',(tester)async{
    late String label;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context){
      label=episodeDateLabel(context,'2026-11-11');
      return const SizedBox();
    })));
    expect(label,contains('Nov'));
    expect(label,contains('2026'));
  });
  testWidgets('episode rail expands only the focused card',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final engine=SeriesEngine();addTearDown(engine.dispose);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:SeriesPage(
      show:const Movie(id:'tmdb:tv:123',title:'Example',type:'Series',tmdbId:123),
      engine:engine,history:History.inMemory(await SharedPreferences.getInstance()))));
    await tester.pumpAndSettle();
    double? width(int n)=>tester.widget<AnimatedContainer>(find.byKey(ValueKey('episode-size-$n'))).constraints?.maxWidth;
    expect(width(1),100);
    expect(width(2),100);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(width(1),252);
    expect(width(2),100);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(width(1),100);
    expect(width(2),252);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(width(2),100);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('legacy movie records remain movies and typed series retain IDs',(){
    final movie=Movie.fromJson({'id':'imdb:tt1234567','title':'Movie'});
    expect(movie.episodic,isFalse);
    final anime=Movie.fromJson({'id':'tmdb:tv:123','tmdbId':123,'title':'Anime','type':'Anime'});
    expect(anime.episodic,isTrue);
    expect(Movie.fromJson(anime.toJson()).type,'Anime');
  });
  test('episode identity is distinct from parent show and other episodes',(){
    const show=Movie(id:'imdb:tt1234567',title:'Example',type:'Series');
    const first=Movie(id:'imdb:tt1234567:s1:e1',title:'Example · S1 E1',type:'Series');
    const second=Movie(id:'imdb:tt1234567:s1:e2',title:'Example · S1 E2',type:'Series');
    const anime=Movie(id:'tmdb:tv:123:s0:e1',title:'Special',type:'Anime');
    expect(show.isEpisode,isFalse);
    expect(first.isEpisode,isTrue);
    expect(anime.isEpisode,isTrue);
    expect(first.id,isNot(second.id));
    expect(Movie.fromJson(first.toJson()).isEpisode,isTrue);
  });
  testWidgets('season tabs load the corresponding episodes',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final history=History.inMemory(await SharedPreferences.getInstance());
    final engine=SeriesEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:SeriesPage(
      show:const Movie(id:'tmdb:tv:123',title:'Example',type:'Anime',tmdbId:123),
      engine:engine,history:history)));
    await tester.pumpAndSettle();
    expect(find.text('Season 1 first'),findsWidgets);
    expect(find.text('Season 2 first'),findsNothing);
    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();
    expect(find.text('Season 2 first'),findsWidgets);
    expect(find.text('Season 1 first'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
