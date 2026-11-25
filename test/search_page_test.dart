import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/search_page.dart';
import 'package:ismegg/design.dart';

class SearchEngine extends NativeEngine {
  SearchEngine(){tv=true;}
  @override Future<String?> providerFor(Movie movie) async=>null;
}

void main(){
  testWidgets('TV search uses explicit native keyboard and shared query',(tester) async {
    final engine=SearchEngine();
    final controller=TextEditingController();
    final page=GlobalKey<CinemaSearchPageState>();
    final queries=<String>[];
    var nav=0;
    addTearDown(engine.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(body:
      CinemaSearchPage(key:page,engine:engine,controller:controller,
        movies:const [Movie(id:'imdb:tt1234567',title:'Example')],
        busy:false,error:null,onQuery:queries.add,onOpen:(_){},onNav:()=>nav++))));
    expect(find.text('Popular movies'),findsOneWidget);
    expect(find.text('Example'),findsOneWidget);
    expect(find.byType(TextField),findsNothing);
    page.currentState!.focusKeyboard();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(controller.text,'A');
    expect(queries.last,'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(page.currentState!.nativeKey.hasFocus,isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(nav,1);
    await tester.tap(find.text('Use TV keyboard'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField),findsOneWidget);
    await tester.enterText(find.byType(TextField),'Batman');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(controller.text,'Batman');
    expect(queries.last,'Batman');
    expect(find.byType(TextField),findsNothing);
    await tester.tap(find.byKey(const ValueKey('search-key-38')));
    await tester.pump();
    expect(controller.text,isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
