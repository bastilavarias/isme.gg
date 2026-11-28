import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/app_preferences.dart';
import 'package:ismegg/back_navigation.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/whats_new/whats_new_controller.dart';

void main(){
  test('only registered, unacknowledged builds are eligible',()async{
    SharedPreferences.setMockInitialValues({});
    final p=await SharedPreferences.getInstance();
    expect(WhatsNewController.pending(p,'0.2.0',17),isTrue);
    expect(WhatsNewController.pending(p,'0.1.0',16),isFalse);
    expect(WhatsNewController.pending(p,'0.2.0',18),isFalse);
    expect(WhatsNewController.pending(p,'2.0.1',18),isTrue);
    await p.setInt(WhatsNewController.acknowledgedKey,17);
    expect(WhatsNewController.pending(p,'0.2.0',17),isFalse);
    expect(WhatsNewController.pending(p,'2.0.1',18),isTrue);
  });

  Future<SharedPreferences> open(WidgetTester tester,{bool upgraded=true,bool preview=false,
    Size size=const Size(412,915),Map<String,Object> saved=const {},
    String version='2.0.1',int code=18})async{
    SharedPreferences.setMockInitialValues(saved);
    final p=await SharedPreferences.getInstance();
    tester.view.physicalSize=size;
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(
      body:Builder(builder:(ctx)=>TextButton(
        onPressed:()=>WhatsNewController.show(ctx,p,version:version,code:code,upgraded:upgraded,preview:preview),
        child:const Text('Open release'))))));
    await tester.tap(find.text('Open release'));
    await tester.pumpAndSettle();
    return p;
  }
  Future<void> confirm(WidgetTester t)async{
    await t.tap(find.text('Continue'));await t.pumpAndSettle();
  }

  testWidgets('update is informational and acknowledged once',(t)async{
    final p=await open(t);
    expect(find.text("You're up to date!"),findsOneWidget);
    expect(find.text('🎉'),findsOneWidget);
    expect(find.text('Successfully updated to v2.0.1'),findsOneWidget);
    expect(find.byType(CheckboxListTile),findsNothing);
    expect(find.text('Native Direct: On  •  Fast Startup: On'),findsOneWidget);
    await confirm(t);
    expect(AppPreferences.nativeDirect(p),isTrue);
    expect(AppPreferences.fastStartup(p),isTrue);
    expect(AppPreferences.adaptiveBuffering(p),isTrue);
    expect(p.containsKey(AppPreferences.nativeDirectKey),isFalse);
    expect(p.getInt(WhatsNewController.acknowledgedKey),18);
    await t.tap(find.text('Open release'));await t.pumpAndSettle();
    expect(find.text("You're up to date!"),findsNothing);
  });
  testWidgets('welcome preserves explicit legacy and fast startup choices',(t)async{
    final p=await open(t,upgraded:false,saved:{
      AppPreferences.nativeDirectKey:false,AppPreferences.fastStartupKey:false,
      AppPreferences.adaptiveBufferingKey:false,
    });
    expect(find.text('Welcome to isme.gg'),findsOneWidget);
    expect(find.text('Native Direct: Off  •  Fast Startup: Off'),findsOneWidget);
    await confirm(t);
    expect(AppPreferences.nativeDirect(p),isFalse);
    expect(AppPreferences.fastStartup(p),isFalse);
    expect(AppPreferences.adaptiveBuffering(p),isFalse);
    expect(p.getInt(WhatsNewController.acknowledgedKey),18);
  });
  testWidgets('TV remote select activates focused Continue',(t)async{
    final p=await open(t,size:const Size(960,540));
    final button=find.byType(FilledButton);
    expect(t.widget<FilledButton>(button).autofocus,isTrue);
    expect(t.getRect(button).bottom,lessThan(540));
    await t.sendKeyEvent(LogicalKeyboardKey.select);await t.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);
    expect(p.getInt(WhatsNewController.acknowledgedKey),18);
  });
  testWidgets('TV Back acknowledges and closes only the modal',(t)async{
    final p=await open(t,size:const Size(960,540));
    // The application gate uses a real monotonic clock, independent of fake
    // frame time in widget tests. Allow the prior test's dismissal to expire.
    await t.runAsync(()=>Future<void>.delayed(appBackGate.cooldown));
    await t.sendKeyEvent(LogicalKeyboardKey.goBack,physicalKey:PhysicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);
    expect(find.text('Open release'),findsOneWidget);
    expect(p.getInt(WhatsNewController.acknowledgedKey),18);
  });
  testWidgets('v2.1.0 mobile modal acknowledges once and preserves playback settings',(t)async{
    final p=await open(t,version:'2.1.0',code:19,saved:{
      WhatsNewController.acknowledgedKey:18,AppPreferences.nativeDirectKey:false,
      AppPreferences.fastStartupKey:false,
    });
    expect(find.text('Meet Isme! 🐾'),findsOneWidget);
    expect(find.text('ISME.GG · VERSION 2.1.0'),findsOneWidget);
    expect(find.text('Cleaner platform icons'),findsOneWidget);
    await t.runAsync(()=>Future<void>.delayed(appBackGate.cooldown));
    await t.tap(find.text('Enjoy the show!'));await t.pumpAndSettle();
    expect(p.getInt(WhatsNewController.acknowledgedKey),19);
    expect(AppPreferences.nativeDirect(p),isFalse);
    expect(AppPreferences.fastStartup(p),isFalse);
    await t.tap(find.text('Open release'));await t.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);
  });
  testWidgets('v2.1.0 TV select acknowledges and debug preview does not persist',(t)async{
    final p=await open(t,version:'2.1.0',code:19,preview:true,size:const Size(960,540));
    final button=find.byType(FilledButton);
    expect(t.widget<FilledButton>(button).autofocus,isTrue);
    expect(t.getRect(button).bottom,lessThan(540));
    await t.runAsync(()=>Future<void>.delayed(appBackGate.cooldown));
    await t.sendKeyEvent(LogicalKeyboardKey.select);await t.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);
    expect(p.containsKey(WhatsNewController.acknowledgedKey),isFalse);
  });
  testWidgets('preview leaves acknowledgment and preferences unchanged',(t)async{
    final p=await open(t,preview:true,saved:{AppPreferences.fastStartupKey:false});
    await confirm(t);
    expect(AppPreferences.nativeDirect(p),isTrue);
    expect(AppPreferences.fastStartup(p),isFalse);
    expect(p.containsKey(WhatsNewController.acknowledgedKey),isFalse);
    await t.tap(find.text('Open release'));await t.pumpAndSettle();
    expect(find.byType(AlertDialog),findsOneWidget);
  });
}
