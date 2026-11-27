import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/app_preferences.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/settings_page.dart';
import 'package:ismegg/support_menu.dart';

void main(){
  test('central settings defaults and Filipino aliases',()async{
    SharedPreferences.setMockInitialValues({});
    final prefs=await SharedPreferences.getInstance();
    expect(AppPreferences.awake(prefs),isTrue);
    expect(AppPreferences.autoplay(prefs),isTrue);
    expect(AppPreferences.nativeDirect(prefs),isTrue);
    await prefs.setBool(AppPreferences.nativeDirectKey,false);
    expect(AppPreferences.nativeDirect(prefs),isFalse);
    await prefs.setBool(AppPreferences.nativeDirectKey,true);
    expect(AppPreferences.nativeDirect(prefs),isTrue);
    expect(AppPreferences.fastStartup(prefs),isTrue);
    await prefs.setBool(AppPreferences.fastStartupKey,false);
    expect(AppPreferences.fastStartup(prefs),isFalse);
    expect(AppPreferences.adaptiveBuffering(prefs),isTrue);
    await prefs.setBool(AppPreferences.adaptiveBufferingKey,false);
    expect(AppPreferences.adaptiveBuffering(prefs),isFalse);
    expect(AppPreferences.subtitles(prefs),'eng');
    expect(AppPreferences.languages.keys,['eng','fil','off']);
    expect(AppPreferences.language('tgl'),'fil');
    expect(AppPreferences.language('tl'),'fil');
    await prefs.setString(AppPreferences.subtitleLanguageKey,'fil');
    expect(AppPreferences.subtitles(prefs),'fil');
  });
  test('clear history leaves saved titles intact after restart',()async{
    SharedPreferences.setMockInitialValues({});
    final prefs=await SharedPreferences.getInstance();
    final storage=MemoryLibraryPersistence();
    final history=await History.open(prefs,persistence:storage);
    const movie=Movie(id:'imdb:tt1234567',title:'Film');
    await history.bookmarks.toggle(movie);
    await history.save(movie,const Duration(seconds:30),const Duration(minutes:2));
    await history.clear();
    final reopened=await History.open(prefs,persistence:storage);
    expect(reopened.movies(),isEmpty);
    expect(reopened.bookmarks.contains(movie),isTrue);
  });
  testWidgets('settings values and switches align to the same trailing edge',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final history=History.inMemory(await SharedPreferences.getInstance()),engine=NativeEngine();
    addTearDown(engine.dispose);
    tester.view.physicalSize=const Size(400,900);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:SettingsPage(engine:engine,history:history)));
    final right=tester.getRect(find.byType(Switch).first).right;
    expect(right,greaterThan(360));
    for(final value in ['English','Medium','Philippines']){
      await tester.ensureVisible(find.text(value));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text(value)).right,closeTo(right,1));
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('settings opens from menu and persists playback toggle',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final prefs=await SharedPreferences.getInstance();
    final history=History.inMemory(prefs),engine=NativeEngine();
    addTearDown(engine.dispose);
    expect(supportMenuItems(engine,includeSettings:true).first,isA<PopupMenuItem<SupportAction>>());
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:SettingsPage(engine:engine,history:history)));
    await tester.tap(find.text('Autoplay next episode'));
    await tester.pumpAndSettle();
    expect(AppPreferences.autoplay(prefs),isFalse);
    await tester.scrollUntilVisible(find.text('Preferred subtitle language'),150,
      scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferred subtitle language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filipino'));
    await tester.pumpAndSettle();
    expect(AppPreferences.subtitles(prefs),'fil');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
