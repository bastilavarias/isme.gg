import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/my_list.dart';
import 'package:ismegg/bookmark_button.dart';
import 'package:ismegg/next_episode.dart';

const film=Movie(id:'imdb:tt1234567',title:'Film',tmdbId:42);
const alias=Movie(id:'tmdb:movie:42',title:'Film',tmdbId:42);
const show=Movie(id:'tmdb:tv:42',title:'Show',tmdbId:42,type:'Series');

void main(){
  test('bookmarks persist separately from history and match known aliases',()async{
    SharedPreferences.setMockInitialValues({});
    final prefs=await SharedPreferences.getInstance();
    final storage=MemoryLibraryPersistence();
    final history=await History.open(prefs,persistence:storage),store=history.bookmarks;
    var changes=0;store.addListener(()=>changes++);
    await store.toggle(film);
    await store.toggle(show);
    expect(store.movies.map((m)=>m.id),[show.id,film.id]);
    expect(store.contains(alias),isTrue);
    expect(history.movies(),isEmpty);
    expect(storage.bookmarks[film.id]!['addedAt'],isA<int>());
    expect(prefs.containsKey('bookmarks-v1'),isFalse);
    final restored=(await History.open(prefs,persistence:storage)).bookmarks;
    expect(restored.movies.map((m)=>m.id),[show.id,film.id]);
    await store.remove(alias);
    expect(store.movies.map((m)=>m.id),[show.id]);
    expect(changes,3);
  });
  test('episode saves its show; serialized writes do not lose items',()async{
    SharedPreferences.setMockInitialValues({});
    final store=History.inMemory(await SharedPreferences.getInstance()).bookmarks;
    final episode=episodeMovie(show,1,const Episode(number:2,title:'Pilot'));
    await Future.wait([store.toggle(episode),store.toggle(film)]);
    expect(store.movies.map((m)=>m.id),[film.id,show.id]);
    expect(store.contains(episode),isTrue);
    await store.toggle(episode);
    expect(store.movies.single.id,film.id);
  });
  test('malformed data loads safely',()async{
    SharedPreferences.setMockInitialValues({'bookmarks-v1':'invalid'});
    final prefs=await SharedPreferences.getInstance();
    final store=(await History.open(prefs,persistence:MemoryLibraryPersistence())).bookmarks;
    expect(prefs.getString('bookmarks-v1'),'invalid');
    expect(store.movies,isEmpty);
    await store.toggle(film);
    expect(store.contains(film),isTrue);
  });
  test('legacy library migrates once without resurrecting removed entries',()async{
    SharedPreferences.setMockInitialValues({
      'bookmarks-v1':jsonEncode([{...film.toJson(),'addedAt':100}]),
      'watch-v1':jsonEncode({show.id:{...show.toJson(),'time':45,'duration':100,'updated':101}}),
    });
    final prefs=await SharedPreferences.getInstance(),storage=MemoryLibraryPersistence();
    final history=await History.open(prefs,persistence:storage);
    expect(history.bookmarks.contains(film),isTrue);
    expect(history.position(show),const Duration(seconds:45));
    expect(history.fraction(show),.45);
    expect(prefs.containsKey('watch-v1'),isFalse);
    expect(prefs.containsKey('bookmarks-v1'),isFalse);
    await history.bookmarks.remove(film);
    await history.save(show,const Duration(seconds:99),const Duration(seconds:100));
    await prefs.setString('bookmarks-v1',jsonEncode([film.toJson()]));
    await prefs.setString('watch-v1',jsonEncode({show.id:{...show.toJson(),'time':45,'duration':100,'updated':101}}));
    final restored=await History.open(prefs,persistence:storage);
    expect(restored.bookmarks.movies,isEmpty);
    expect(restored.movies(),isEmpty);
  });
  test('refresh reads persisted rows and respects queued writes',()async{
    SharedPreferences.setMockInitialValues({});
    final storage=MemoryLibraryPersistence();
    final history=await History.open(await SharedPreferences.getInstance(),persistence:storage);
    await storage.writeBookmark(film.id,{...film.toJson(),'addedAt':1});
    expect(history.bookmarks.movies,isEmpty);
    await history.bookmarks.refresh();
    expect(history.bookmarks.contains(film),isTrue);
    await Future.wait([history.bookmarks.remove(film),history.bookmarks.refresh()]);
    expect(history.bookmarks.movies,isEmpty);
  });
  testWidgets('TV remote press saves once even when Select repeats',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final history=History.inMemory(await SharedPreferences.getInstance());
    final focus=FocusNode();addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(
      body:Center(child:BookmarkButton(movie:film,store:history.bookmarks,tv:true,focusNode:focus)))));
    focus.requestFocus();await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(history.bookmarks.contains(film),isTrue);
    await tester.pump(const Duration(milliseconds:500));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(history.bookmarks.contains(film),isTrue);
    expect(find.text('Saved'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('TV opens a saved poster with Select and restores focus after Back',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final history=History.inMemory(await SharedPreferences.getInstance());
    await history.bookmarks.toggle(film);
    final engine=NativeEngine()..tv=true;addTearDown(engine.dispose);
    tester.view.physicalSize=const Size(1280,720);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:MyList(
      store:history.bookmarks,engine:engine,tv:true,onOpen:(ctx,m)async{
        await Navigator.of(ctx).push<void>(MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:Text(m.title)))));
      })));
    await tester.pumpAndSettle();
    final tile=find.byKey(ValueKey('saved-${film.id}'));
    final node=tester.widget<RemoteTile>(tile).focusNode!;
    node.requestFocus();await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar,'Film'),findsOneWidget);
    await tester.tap(find.byType(BackButton));await tester.pumpAndSettle();
    expect(node.hasFocus,isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
