import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/platform_rail.dart';
import 'package:ismegg/platform_logos.dart';
import 'package:ismegg/design.dart';

void main(){
  testWidgets('all twelve bundled logos decode without metadata credentials',(tester)async{
    await tester.runAsync(()async{
      for(final brand in PlatformBrand.brands.skip(1)){
        final bytes=bundledPlatformLogo(brand.key);
        expect(bytes,isNotNull,reason:brand.name);
        final codec=await ui.instantiateImageCodec(bytes!);
        final frame=await codec.getNextFrame();
        expect(frame.image.width,greaterThan(0));
        expect(frame.image.height,greaterThan(0));
        frame.image.dispose();codec.dispose();
      }
    });
    expect(bundledPlatformLogo('all'),isNull);
  });
  test('platform aliases use exact provider names, not unrelated channels',(){
    final prime=PlatformBrand.brands.firstWhere((b)=>b.key=='prime');
    const rows=[
      WatchProvider(id:1,name:'Amazon Prime Video',movie:true,tv:true),
      WatchProvider(id:2,name:'Amazon Prime Video with Ads',tv:true),
      WatchProvider(id:3,name:'Paramount Plus Amazon Channel',movie:true),
    ];
    expect(prime.matches(rows).map((p)=>p.id),[1,2]);
  });
  testWidgets('filtered platform rail keeps All visible when far-end service is selected',(tester)async{
    final key=GlobalKey<PlatformRailState>();
    final chosen=<String>[];
    final selected=PlatformBrand.brands.last;
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(body:PlatformRail(
      key:key,providers:const [],selected:selected,tv:true,
      onSelected:(p)=>chosen.add(p.key),onUp:(){},onDown:(){}))));
    await tester.pumpAndSettle();
    final all=find.byKey(const ValueKey('platform-all'));
    final allPosition=tester.getTopLeft(all);
    expect(all.hitTestable(),findsOneWidget);
    expect(key.currentState!.scroll.offset,greaterThan(0));
    key.currentState!.focusRemembered();
    await tester.pumpAndSettle();
    expect(key.currentState!.nodes.last.hasFocus,isTrue);
    expect(tester.getTopLeft(all),allPosition);
    key.currentState!.focusAt(0);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(chosen,['all']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('D-pad focus previews platform; select commits only on activation',(tester)async{
    final key=GlobalKey<PlatformRailState>();
    final chosen=<String>[];
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(body:PlatformRail(
      key:key,providers:const [],selected:PlatformBrand.all,tv:true,
      onSelected:(p)=>chosen.add(p.key),onUp:(){},onDown:(){}))));
    key.currentState!.focusRemembered();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(chosen,isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(chosen,['netflix']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
