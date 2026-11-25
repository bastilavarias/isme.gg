import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/support_menu.dart';
import 'package:ismegg/design.dart';

class SupportTestEngine extends NativeEngine {
  int resets=0,checks=0,reports=0;
  final guard=<bool>[];
  @override Future<void> setSupportUiActive(bool active) async {guard.add(active);}
  @override Future<void> openIssueReport() async {reports++;}
  @override Future<bool> clearLocalData() async {resets++;return true;}
  @override Future<void> checkUpdates() async {checks++;}
}

void main(){
  test('menu contains three actions with a divider before updates',(){
    final e=SupportTestEngine()..appVersion='1.2.3';
    addTearDown(e.dispose);
    final items=supportMenuItems(e);
    expect(items.length,4);
    expect((items[0] as PopupMenuItem<SupportAction>).value,SupportAction.report);
    expect((items[1] as PopupMenuItem<SupportAction>).value,SupportAction.clear);
    expect(items[2],isA<PopupMenuDivider>());
    expect((items[3] as PopupMenuItem<SupportAction>).value,SupportAction.update);
    expect(installedVersion(e),'v1.2.3');
    expect(issueQrModules.length,41);
    expect(issueQrModules.every((row)=>row.length==41),isTrue);
    expect(reportIssueUrl,'https://github.com/bastilavarias/isme.gg/issues/new');
  });
  testWidgets('report uses local QR and can close or open browser on phone',(tester)async{
    final e=SupportTestEngine();addTearDown(e.dispose);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(body:Builder(
      builder:(ctx)=>TextButton(onPressed:()=>openSupportMenu(ctx,e,()=>showSupportSheet(ctx,e)),child:const Text('Menu'))))));
    await tester.tap(find.text('Menu'));await tester.pumpAndSettle();
    expect(find.text('Report a problem'),findsOneWidget);
    expect(find.text('Clear local data'),findsOneWidget);
    expect(find.text('Check updates'),findsOneWidget);
    expect(find.text('Refresh catalogs'),findsNothing);
    await tester.tap(find.text('Report a problem'));await tester.pumpAndSettle();
    expect(find.text(reportIssueUrl),findsOneWidget);
    await tester.tap(find.text('Open in browser'));await tester.pumpAndSettle();
    expect(e.reports,1);
    await tester.tap(find.text('Close'));await tester.pumpAndSettle();
    expect(e.guard,[true,false]);
    expect(e.resets,0);
  });
  testWidgets('reset only runs after explicit confirmation',(tester)async{
    final e=SupportTestEngine();addTearDown(e.dispose);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(body:Builder(
      builder:(ctx)=>TextButton(onPressed:()=>confirmClearLocalData(ctx,e),child:const Text('Reset'))))));
    await tester.tap(find.text('Reset'));await tester.pumpAndSettle();
    expect(find.text('Clear local data?'),findsOneWidget);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
    expect(e.resets,0);
    await tester.tap(find.text('Reset'));await tester.pumpAndSettle();
    await tester.tap(find.text('Clear data'));await tester.pumpAndSettle();
    expect(e.resets,1);
  });
  testWidgets('manual check runs after the menu guard is released',(tester)async{
    final e=SupportTestEngine()..appVersion='1.2.3';addTearDown(e.dispose);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(body:Builder(
      builder:(ctx)=>TextButton(onPressed:()=>openSupportMenu(ctx,e,()=>showSupportSheet(ctx,e)),child:const Text('Menu'))))));
    await tester.tap(find.text('Menu'));await tester.pumpAndSettle();
    expect(find.text('v1.2.3'),findsOneWidget);
    await tester.tap(find.text('Check updates'));await tester.pumpAndSettle();
    expect(e.guard,[true,false]);
    expect(e.checks,1);
  });
}
