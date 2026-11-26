import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/back_navigation.dart';

void main(){
  test('back gate drops duplicate actions and allows deliberate presses',(){
    var time=Duration.zero;
    final gate=BackPressGate(now:()=>time);
    expect(gate.accept(),isTrue);
    time=const Duration(milliseconds:100);
    expect(gate.accept(),isFalse);
    time=const Duration(milliseconds:400);
    expect(gate.accept(),isTrue);
    time=const Duration(milliseconds:700);
    gate.block();
    time=const Duration(milliseconds:900);
    expect(gate.accept(),isFalse);
    time=const Duration(milliseconds:1100);
    expect(gate.accept(),isTrue);
  });

  test('TV Back hides active controls before leaving playback',(){
    expect(backHidesPlaybackControls(tv:true,controlsVisible:true,playbackReady:true),isTrue);
    expect(backHidesPlaybackControls(tv:true,controlsVisible:false,playbackReady:true),isFalse);
    expect(backHidesPlaybackControls(tv:true,controlsVisible:true,playbackReady:false),isFalse);
    expect(backHidesPlaybackControls(tv:true,controlsVisible:false,playbackReady:false),isFalse);
  });
  test('mobile Back leaves regardless of controls or playback readiness',(){
    for(final controls in [true,false]){
      for(final ready in [true,false]){
        expect(backHidesPlaybackControls(tv:false,controlsVisible:controls,playbackReady:ready),isFalse);
      }
    }
  });

  test('exit counter needs three presses inside a short window',(){
    final counter=ExitPressCounter();
    expect(counter.press(Duration.zero),1);
    expect(counter.press(const Duration(milliseconds:600)),2);
    expect(counter.press(const Duration(seconds:4)),1);
    expect(counter.press(const Duration(milliseconds:4500)),2);
    expect(counter.press(const Duration(seconds:5)),3);
    counter.reset();
    expect(counter.press(const Duration(seconds:6)),1);
  });

  testWidgets('home requires three distinct back presses; timeout resets count',(tester)async{
    var time=Duration.zero;
    var exits=0;
    final gate=BackPressGate(now:()=>time);
    final nav=GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey:nav,home:HomeBackGuard(
      gate:gate,locationKey:'Home',navigateHome:()=>false,
      exitApp:()async{exits++;},
      child:const Scaffold(body:Text('Home')))));
    Future<void> back(int ms) async{
      time=Duration(milliseconds:ms);
      await nav.currentState!.maybePop();
      await tester.pump(const Duration(milliseconds:300));
    }
    await back(0);
    expect(find.text('Press Back 2 more times to exit'),findsOneWidget);
    await back(100);
    expect(exits,0);
    await back(500);
    expect(find.text('Press Back once more to exit'),findsOneWidget);
    await back(4000);
    expect(exits,0);
    await back(4500);
    await back(5000);
    expect(exits,1);
    expect(find.text('Home'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('category back returns home without counting toward exit',(tester)async{
    var time=Duration.zero;
    var category='Movies';
    var exits=0;
    final gate=BackPressGate(now:()=>time);
    final nav=GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey:nav,home:StatefulBuilder(builder:(context,update)=>
      HomeBackGuard(gate:gate,locationKey:category,navigateHome:(){
        if(category=='Home')return false;
        update(()=>category='Home');return true;
      },exitApp:()async{exits++;},child:Scaffold(body:Text(category))))));
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Home'),findsOneWidget);
    expect(find.text('Press Back 2 more times to exit'),findsNothing);
    time=const Duration(milliseconds:500);
    await nav.currentState!.maybePop();
    await tester.pump(const Duration(milliseconds:300));
    expect(find.text('Press Back 2 more times to exit'),findsOneWidget);
    expect(exits,0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resume stack keeps title details under player; delayed cleanup pops exactly once',(tester)async{
    var time=Duration.zero;
    final gate=BackPressGate(now:()=>time);
    final nav=GlobalKey<NavigatorState>();
    final cleanup=Completer<void>();
    var closing=false;
    await tester.pumpWidget(MaterialApp(navigatorKey:nav,home:Builder(builder:(context)=>Scaffold(
      body:TextButton(onPressed:(){
        unawaited(pushTitleRoute(context,BackNavigationScope(gate:gate,child:const Scaffold(body:Text('Title details'))),
          resumePlayer:Builder(builder:(playerContext)=>BackNavigationScope(gate:gate,onBack:(){
            if(closing)return;
            closing=true;
            unawaited(cleanup.future.then((_){popCurrentPage(playerContext,gate:gate);}));
          },child:const Scaffold(body:Text('Player'))))));
      },child:const Text('Resume'))))));
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.text('Player'),findsOneWidget);
    await nav.currentState!.maybePop();
    time=const Duration(milliseconds:500);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Player'),findsOneWidget);
    time=const Duration(seconds:2);
    cleanup.complete();
    await tester.pumpAndSettle();
    expect(find.text('Title details'),findsOneWidget);
    await nav.currentState!.maybePop(); // duplicate event from the player
    await tester.pumpAndSettle();
    expect(find.text('Title details'),findsOneWidget);
    time=const Duration(milliseconds:2500);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Resume'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('held escape key does not count as multiple Back taps',(tester)async{
    var time=Duration.zero;
    var exits=0;
    final gate=BackPressGate(now:()=>time);
    await tester.pumpWidget(MaterialApp(home:HomeBackGuard(
      gate:gate,locationKey:'Home',navigateHome:()=>false,exitApp:()async{exits++;},
      child:const Scaffold(body:Focus(autofocus:true,child:Text('Home'))))));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds:300));
    time=const Duration(milliseconds:800);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
    time=const Duration(milliseconds:1600);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds:300));
    expect(exits,0);
    expect(find.text('Press Back 2 more times to exit'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
