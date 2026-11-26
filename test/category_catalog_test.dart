import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/category_catalog.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/home_sections.dart';
import 'package:ismegg/main.dart';
import 'package:ismegg/next_episode.dart';
import 'package:ismegg/search_page.dart';
import 'package:ismegg/platform_rail.dart';

class CategoryTestEngine extends NativeEngine {
  final requested=<String>[];
  Completer<CatalogSnapshot>? blockedMovieRecent;
  bool recentRequested=false;
  @override bool get providersConfigured=>true;
  CatalogSnapshot fixture(String key){
    final anime=key=='weekly_anime'||key.startsWith('page_anime_')&&key!='page_anime_movies'||key=='anime';
    final series=key=='weekly_series'||key=='weekly_tv'||key.startsWith('page_series_')||key=='page_pinoy_series';
    return CatalogSnapshot(List.generate(3,(i)=>Movie(id:'$key:$i',title:'$key title $i',
      poster:'fixture',type:anime?'Anime':series?'Series':'Movie',
      animeFilm:key=='page_anime_movies',pinoy:key.startsWith('page_pinoy_')||key=='pinoy_home')),
      cacheHit:true,stale:false,source:weeklySectionKeys.contains(key)?'tmdb_weekly':'tmdb');
  }
  @override Future<CatalogSnapshot> catalogSnapshot(String collection,{String mode='normal',String query=''})async{
    requested.add(collection);
    if(collection=='page_movies_recent'&&blockedMovieRecent!=null){
      recentRequested=true;return blockedMovieRecent!.future;
    }
    return fixture(collection);
  }
  @override Future<List<WatchProvider>> watchPlatforms({String mode='normal',bool artworkOnly=false})async=>const [
    WatchProvider(id:8,name:'Netflix',movie:true,tv:true),
    WatchProvider(id:337,name:'Disney Plus',movie:true,tv:true),
  ];
  @override Future<CatalogSnapshot> platformCatalog(List<int> ids,String kind,String row,{String mode='normal'})async=>
    fixture('platform:${ids.join(",")}:$kind:$row');
  @override Future<String?> providerFor(Movie movie)async=>null;
}

void main(){
  test('all category definitions are distinct, ordered, and contain editorial rows',(){
    final pages=[for(final name in categoryNames.skip(1))categorySections(name,weeklySectionKeys)];
    expect(pages.map((p)=>p.keys.first),orderedEquals(['weekly_movies','weekly_series','weekly_anime','page_pinoy_movies']));
    for(final page in pages){
      expect(page.length,greaterThanOrEqualTo(8));
      expect(page.keys.every(editorialCollection),isTrue);
      expect(page.values.toSet().length,page.length);
    }
    expect(categorySections('Series',weeklySectionKeys),categorySections('TV Series',weeklySectionKeys));
    expect(categorySections('Anime',{})['weekly_anime'],'Popular anime');
    expect(isRankedSection(categorySections('Anime',weeklySectionKeys)['weekly_anime']!),isTrue);
    expect(categorySections('Pinoy',{})['page_pinoy_movies'],'Popular Pinoy Movies');
    expect(editorialFallback.containsKey('page_pinoy_indie'),isFalse);
    expect(editorialFallback.containsKey('page_anime_airing'),isFalse);
  });
  test('category membership preserves movie and series identity and explicit regional tags',(){
    const anime=Movie(id:'tmdb:movie:11',title:'Film',tmdbId:11,animeFilm:true);
    const pinoy=Movie(id:'tmdb:tv:12',title:'Show',tmdbId:12,type:'Series',pinoy:true);
    final episode=episodeMovie(pinoy,1,const Episode(number:2,title:'Pilot'));
    final restored=Movie.fromJson(episode.toJson());
    expect(belongsToCategory(anime,'Movies',[]),isTrue);
    expect(belongsToCategory(anime,'Anime',[]),isTrue);
    expect(anime.episodic,isFalse);
    expect(restored.pinoy,isTrue);
    expect(EpisodeIdentity.parse(restored)!.parent(restored).pinoy,isTrue);
    expect(belongsToCategory(restored,'TV Series',[]),isTrue);
    expect(belongsToCategory(restored,'Pinoy',[]),isTrue);
    expect(belongsToCategory(restored,'Anime',[]),isFalse);
    expect(resumeTitle(episode),episode.title);
    const legacy=Movie(id:'imdb:tt1234567',title:'Legacy',tmdbId:11);
    expect(belongsToCategory(legacy,'Anime',[anime]),isTrue);
    const otherType=Movie(id:'tmdb:tv:11',title:'Unrelated',tmdbId:11,type:'Series');
    expect(belongsToCategory(otherType,'Anime',[anime]),isFalse);
    expect(belongsToCategory(legacy,'Pinoy',[]),isFalse);
    expect(editorialFallbackMovies('page_pinoy_classics',[
      const Movie(id:'1',title:'Old',year:'1998'),const Movie(id:'2',title:'New',year:'2024')
    ]).map((m)=>m.id),['1']);
  });
  testWidgets('TV platform filter relocates selector, preserves focus, and All restores Home',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final engine=CategoryTestEngine()..tv=true;
    addTearDown(engine.dispose);
    final history=History(await SharedPreferences.getInstance());
    tester.view.physicalSize=const Size(1280,720);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:deviceHome(engine,history)));
    await tester.pumpAndSettle();
    final rail=find.byType(PlatformRail);
    PlatformRailState state()=>tester.state<PlatformRailState>(rail);
    expect(rail,findsOneWidget);
    expect(tester.getTopLeft(rail).dy,greaterThan(tester.getTopLeft(find.text('Top 10 Movies This Week')).dy));
    state().focusAt(1);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog:Home:netflix')),findsOneWidget);
    expect(rail,findsOneWidget);
    expect(state().nodes[1].hasFocus,isTrue);
    expect(find.byKey(const ValueKey('platform-all')).hitTestable(),findsOneWidget);
    expect(tester.getTopLeft(rail).dy,lessThan(tester.getTopLeft(find.text('Popular movies')).dy));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog:Home:disney')),findsOneWidget);
    expect(state().nodes[2].hasFocus,isTrue);
    state().focusAt(0);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog:Home:all')),findsOneWidget);
    expect(tester.getTopLeft(rail).dy,greaterThan(tester.getTopLeft(find.text('Top 10 Movies This Week')).dy));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('TV navbar switches on remote focus but Search and Menu require Select',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final engine=CategoryTestEngine()..tv=true;
    addTearDown(engine.dispose);
    final history=History(await SharedPreferences.getInstance());
    tester.view.physicalSize=const Size(1280,720);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:deviceHome(engine,history)));
    await tester.pumpAndSettle();
    FocusNode tab(String label)=>tester.widget<TextButton>(find.byKey(ValueKey('nav-$label'))).focusNode!;
    Future<void> right()async{
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    void page(String section)=>expect(find.byKey(ValueKey('catalog:$section:all')),findsOneWidget);
    tab('Home').requestFocus();
    await tester.pumpAndSettle();
    page('Home');
    await right();
    expect(tab('Search').hasFocus,isTrue);
    page('Home');
    expect(find.byType(CinemaSearchPage),findsNothing);
    await right();
    page('Movies');
    expect(tab('Movies').hasFocus,isTrue);
    await right();
    page('Series');
    await right();
    page('Anime');
    await right();
    page('Pinoy');
    await right();
    page('Pinoy');
    expect(find.byType(PopupMenuItem),findsNothing);
    expect(tester.widget<IconButton>(find.byTooltip('Menu')).focusNode!.hasFocus,isTrue);
    tab('Search').requestFocus();
    await tester.pumpAndSettle();
    page('Pinoy');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(CinemaSearchPage),findsOneWidget);
    tab('Home').requestFocus();
    await tester.pumpAndSettle();
    page('Home');
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for(final tv in [true,false]){
    testWidgets('${tv?"TV":"Mobile"}: category nav loads independent catalogs and ignores a late response',(tester)async{
      SharedPreferences.setMockInitialValues({});
      final engine=CategoryTestEngine()..tv=tv;
      addTearDown(engine.dispose);
      final history=History(await SharedPreferences.getInstance());
      tester.view.physicalSize=tv?const Size(1280,720):const Size(390,844);
      tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:deviceHome(engine,history)));
      await tester.pumpAndSettle();
      Future<void> select(String label,{bool remote=false})async{
        final target=find.byKey(ValueKey('${tv?"nav":"mobile-nav"}-$label'));
        await tester.ensureVisible(target);
        if(remote&&tv){
          tester.widget<TextButton>(target).focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        }else{await tester.tap(target);}
        await tester.pump();
      }
      void expectPage(String label){
        if(tv){
          expect(find.byKey(ValueKey('catalog:${label=="TV Series"?"Series":label}:all')),findsOneWidget);
        }else{
          final heading=tester.widget<Text>(find.byKey(const ValueKey('mobile-catalog-heading')));
          expect(heading.data,label);
        }
      }
      engine.blockedMovieRecent=Completer<CatalogSnapshot>();
      await select('Movies',remote:true);
      for(var i=0;i<5&&!engine.recentRequested;i++){await tester.pump(const Duration(milliseconds:20));}
      expect(engine.recentRequested,isTrue);
      expectPage('Movies');
      await select('Anime');
      await tester.pumpAndSettle();
      expectPage('Anime');
      expect(engine.requested,contains('page_anime_movies'));
      engine.blockedMovieRecent!.complete(engine.fixture('page_movies_recent'));
      await tester.pumpAndSettle();
      expectPage('Anime');
      expect(find.text('Recently Released'),findsNothing);
      for(final label in ['TV Series','Pinoy']){
        await select(label);
        await tester.pumpAndSettle();
        expectPage(label);
        final first=categorySections(label,weeklySectionKeys).values.first;
        expect(find.text(first),findsOneWidget);
      }
      await select('Home');
      await tester.pumpAndSettle();
      if(tv)expect(find.byKey(const ValueKey('catalog:Home:all')),findsOneWidget);
      else expect(find.byKey(const ValueKey('mobile-catalog-heading')),findsNothing);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
