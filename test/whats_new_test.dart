import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ismegg/app_preferences.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/whats_new/whats_new_controller.dart';

void main(){
  test('only registered, unacknowledged builds are eligible',()async{
    SharedPreferences.setMockInitialValues({});
    final p=await SharedPreferences.getInstance();
    expect(WhatsNewController.pending(p,'0.2.0',17),isTrue);
    expect(WhatsNewController.pending(p,'0.1.0',16),isFalse);
    expect(WhatsNewController.pending(p,'0.2.0',18),isFalse);
    await p.setInt(WhatsNewController.acknowledgedKey,17);
    expect(WhatsNewController.pending(p,'0.2.0',17),isFalse);
  });

  Future<SharedPreferences> open(WidgetTester tester,{bool upgraded=true,bool preview=false})async{
    SharedPreferences.setMockInitialValues({});
    final p=await SharedPreferences.getInstance();
    tester.view.physicalSize=const Size(412,915);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(
      body:Builder(builder:(ctx)=>TextButton(
        onPressed:()=>WhatsNewController.show(ctx,p,version:'0.2.0',code:17,upgraded:upgraded,preview:preview),
        child:const Text('Open release'))))));
    await tester.tap(find.text('Open release'));
    await tester.pumpAndSettle();
    return p;
  }
  Future<void> toggle(WidgetTester t,String label)async{
    await t.ensureVisible(find.text(label));await t.pumpAndSettle();
    await t.tap(find.text(label));await t.pumpAndSettle();
  }
  Future<void> confirm(WidgetTester t)async{
    await t.tap(find.text('Continue'));await t.pumpAndSettle();
  }

  testWidgets('updated users can keep HTTP and acknowledge only once',(t)async{
    final p=await open(t);
    expect(find.text("You're up to date!"),findsOneWidget);
    expect(find.text('🎉'),findsOneWidget);
    expect(find.text('Successfully updated to v0.2.0'),findsOneWidget);
    expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile).last).onChanged,isNull);
    await confirm(t);
    expect(AppPreferences.nativeDirect(p),isFalse);
    expect(AppPreferences.fastStartup(p),isFalse);
    expect(AppPreferences.adaptiveBuffering(p),isFalse);
    expect(p.getInt(WhatsNewController.acknowledgedKey),17);
    await t.tap(find.text('Open release'));await t.pumpAndSettle();
    expect(find.text("You're up to date!"),findsNothing);
  });
  testWidgets('welcome dialog opts into native and fast only on confirmation',(t)async{
    final p=await open(t,upgraded:false);
    expect(find.text('Welcome to isme.gg'),findsOneWidget);
    await toggle(t,'Enable Native Direct');
    await toggle(t,'Enable Fast Startup');
    expect(AppPreferences.nativeDirect(p),isFalse);
    expect(p.containsKey(WhatsNewController.acknowledgedKey),isFalse);
    await confirm(t);
    expect(AppPreferences.nativeDirect(p),isTrue);
    expect(AppPreferences.fastStartup(p),isTrue);
    expect(AppPreferences.adaptiveBuffering(p),isTrue);
    expect(p.getInt(WhatsNewController.acknowledgedKey),17);
  });
  testWidgets('preview does not acknowledge and native alone keeps fast off',(t)async{
    final p=await open(t,preview:true);
    await toggle(t,'Enable Native Direct');
    await confirm(t);
    expect(AppPreferences.nativeDirect(p),isTrue);
    expect(AppPreferences.fastStartup(p),isFalse);
    expect(AppPreferences.adaptiveBuffering(p),isTrue);
    expect(p.containsKey(WhatsNewController.acknowledgedKey),isFalse);
    await t.tap(find.text('Open release'));await t.pumpAndSettle();
    expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value,isTrue);
    await toggle(t,'Enable Native Direct');
    await confirm(t);
    expect(AppPreferences.nativeDirect(p),isFalse);
  });
}
