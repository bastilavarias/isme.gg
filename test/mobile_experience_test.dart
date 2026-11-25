import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/main.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/mobile/mobile_home.dart';
import 'package:ismegg/mobile/mobile_library.dart';
import 'package:ismegg/mobile/mobile_details.dart';

class MobileTestEngine extends NativeEngine{
  static const film=Movie(id:'imdb:tt1234567',title:'Example film');
  static const show=Movie(id:'imdb:tt1234568',title:'Example series',type:'Series');
  @override Future<CatalogSnapshot> catalogSnapshot(String collection,{String mode='normal',String query=''}) async=>
    CatalogSnapshot(collection=='trending'?[film]:collection=='series'?[show]:[],cacheHit:true,stale:false);
  @override Future<List<WatchProvider>> watchPlatforms({String mode='normal',bool artworkOnly=false})async=>[];
  @override Future<String?> providerFor(Movie movie) async=>null;
  @override Future<List<Season>> seasons(Movie show) async=>const [Season(1,'Season 1'),Season(2,'Season 2')];
  @override Future<List<Episode>> episodes(Movie show,int season)async=>[Episode(number:1,title:'Pilot $season'),const Episode(number:2,title:'Episode 2')];
}
void main(){
  test('TV always keeps its existing shell; phone uses a separate shell',()async{
    SharedPreferences.setMockInitialValues({});
    final history=History(await SharedPreferences.getInstance());
    final engine=MobileTestEngine();addTearDown(engine.dispose);
    expect(deviceHome(engine,history),isA<MobileHome>());
    engine.tv=true;
    expect(deviceHome(engine,history),isA<CinemaHome>());
  });
  test('bookmarks are local and watch progress remains backward compatible',()async{
    SharedPreferences.setMockInitialValues({});
    final history=History(await SharedPreferences.getInstance()),library=MobileLibrary(History(await SharedPreferences.getInstance()));
    const film=MobileTestEngine.film;
    await library.toggle(film);expect(library.contains(film),isTrue);
    await history.save(film,const Duration(seconds:30),const Duration(seconds:100));
    expect(library.fraction(film),.3);
    expect(history.position(film),const Duration(seconds:30));
    await library.toggle(film);expect(library.contains(film),isFalse);
  });
  testWidgets('mobile shell switches navigation without TV expansion',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final engine=MobileTestEngine();addTearDown(engine.dispose);
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final history=History(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:deviceHome(engine,history)));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar),findsOneWidget);
    expect(find.text('Explore platforms'),findsOneWidget);
    await tester.tap(find.text('Search'));await tester.pumpAndSettle();
    expect(find.byType(TextField),findsOneWidget);
    await tester.tap(find.text('My List'));await tester.pumpAndSettle();
    expect(find.text('Your list is empty'),findsOneWidget);
    tester.view.physicalSize=const Size(844,390);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('mobile episodes list and season sheet work without TV focus widgets',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final engine=MobileTestEngine();addTearDown(engine.dispose);
    final library=MobileLibrary(History(await SharedPreferences.getInstance()));
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:MobileDetails(movie:MobileTestEngine.show,engine:engine,library:library)));
    await tester.pumpAndSettle();
    expect(find.text('Pilot 1'),findsOneWidget);
    await tester.tap(find.text('Season 1'));await tester.pumpAndSettle();
    await tester.tap(find.text('Season 2'));await tester.pumpAndSettle();
    expect(find.text('Pilot 2'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
