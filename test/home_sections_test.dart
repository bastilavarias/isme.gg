import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/home_sections.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/main.dart';
import 'package:ismegg/design.dart';

class HomeTestEngine extends NativeEngine {
  @override Future<CatalogSnapshot> catalogSnapshot(String collection,{String mode='normal',String query=''}) async {
    final weekly=weeklySectionKeys.contains(collection);
    return CatalogSnapshot([
      Movie(id:'$collection:1',title:'$collection item',type:collection=='weekly_tv'?'Series':'Movie',poster:'fixture'),
      if(weekly)Movie(id:'$collection:2',title:'$collection second',poster:'fixture')
    ],cacheHit:true,stale:false,source:weekly?'tmdb_weekly':'tmdb');
  }
  @override Future<List<WatchProvider>> watchPlatforms({String mode='normal',bool artworkOnly=false})async=>[];
  @override Future<String?> providerFor(Movie movie)async=>null;
}

void main(){
  test('same ordered home contract and honest ranking labels',(){
    final verified=<String>{};
    final fallback=CatalogSnapshot([const Movie(id:'m',title:'M')],cacheHit:true,stale:false,source:'fallback');
    rememberWeekly(verified,'weekly_movies',fallback);
    expect(homeSections(verified).keys,orderedEquals(homeSectionKeys));
    expect(homeSections(verified)['weekly_movies'],'Trending movies');
    final rows=List.generate(15,(i)=>Movie(id:'m$i',title:'Title $i'));
    final genuine=CatalogSnapshot([rows.first,...rows],cacheHit:false,stale:false,source:'tmdb_weekly');
    rememberWeekly(verified,'weekly_movies',genuine);
    expect(homeSections(verified)['weekly_movies'],'Top 10 Movies This Week');
    expect(sectionMovies('weekly_movies',genuine).map((m)=>m.id),orderedEquals(rows.take(10).map((m)=>m.id)));
    rememberWeekly(verified,'weekly_movies',fallback);
    expect(isRankedSection(homeSections(verified)['weekly_movies']!),isFalse);
  });
  test('daily featured titles are deterministic and unique',(){
    final candidates=List.generate(8,(i)=>Movie(id:'m$i',title:'Title $i',poster:'fixture'));
    final picks=featuredToday([...candidates,candidates.first],now:DateTime(2026,11,26));
    final again=featuredToday(candidates,now:DateTime(2026,11,26));
    expect(picks.map((m)=>m.id),orderedEquals(again.map((m)=>m.id)));
    expect(picks.length,4);
    expect(featuredToday(candidates,now:DateTime(2026,11,27)).first.id,isNot(picks.first.id));
  });
  test('shared resume information includes episode label and real percentage',()async{
    SharedPreferences.setMockInitialValues({});
    final history=History.inMemory(await SharedPreferences.getInstance());
    const ep=Movie(id:'imdb:tt1234567:s2:e3',title:'Show',type:'Series');
    expect(resumeTitle(ep),'Show · S2 E3');
    expect(history.fraction(ep),isNull);
    await history.save(ep,const Duration(seconds:30),const Duration(seconds:100));
    expect(history.fraction(ep),.3);
  });
  for(final tv in [true,false]){
    testWidgets('${tv?"TV":"Mobile"} uses ranked sections and places platforms last',(tester)async{
      SharedPreferences.setMockInitialValues({});
      final engine=HomeTestEngine()..tv=tv;
      addTearDown(engine.dispose);
      tester.view.physicalSize=tv?const Size(1280,720):const Size(390,844);
      tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final history=History.inMemory(await SharedPreferences.getInstance());
      await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:deviceHome(engine,history)));
      await tester.pumpAndSettle();
      final labels=homeSections(weeklySectionKeys).values.toList();
      expect(find.text(labels.first),findsOneWidget);
      final scroll=find.descendant(of:tv?find.byKey(const ValueKey('tv-home-scroll')):
        find.byKey(const PageStorageKey('mobile-home')),matching:find.byType(Scrollable)).first;
      for(final label in labels.skip(1)){
        await tester.scrollUntilVisible(find.text(label),200,scrollable:scroll);
        expect(find.text(label),findsOneWidget);
      }
      await tester.scrollUntilVisible(find.text('Explore platforms'),200,scrollable:scroll);
      expect(find.text('Explore platforms'),findsOneWidget);
      expect(find.textContaining('Availability: JustWatch'),findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(),isNull);
    });
  }
}
