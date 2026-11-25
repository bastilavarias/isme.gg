import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/platform_rail.dart';
import 'package:ismegg/design.dart';

void main(){
  test('platform aliases use exact provider names, not unrelated channels',(){
    final prime=PlatformBrand.brands.firstWhere((b)=>b.key=='prime');
    const rows=[
      WatchProvider(id:1,name:'Amazon Prime Video',movie:true,tv:true),
      WatchProvider(id:2,name:'Amazon Prime Video with Ads',tv:true),
      WatchProvider(id:3,name:'Paramount Plus Amazon Channel',movie:true),
    ];
    expect(prime.matches(rows).map((p)=>p.id),[1,2]);
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
