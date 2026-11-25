import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/cinema_shelf.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';

void main() {
  const movies = [
    Movie(id:'a', title:'First', year:'2026', description:'First synopsis'),
    Movie(id:'b', title:'Second', description:'Second synopsis'),
    Movie(id:'c', title:'Third'),
  ];
  testWidgets('Only focused card expands; D-pad moves and opens it', (tester) async {
    final shelf = GlobalKey<CinemaShelfState>();
    final outside = FocusNode();
    addTearDown(outside.dispose);
    Movie? highlighted, opened;
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(), home:Scaffold(
      body:Column(children:[
        TextButton(focusNode:outside,onPressed:(){},child:const Text('Home')),
        CinemaShelf(key:shelf,title:'Trending',movies:movies,
          onHighlight:(m)=>highlighted=m,onOpen:(m)=>opened=m),
      ]),
    )));
    final first=find.byKey(const ValueKey('size-a'));
    final second=find.byKey(const ValueKey('size-b'));
    expect(tester.getSize(first).width,132);
    shelf.currentState!.focusRemembered();
    await tester.pumpAndSettle();
    expect(tester.getSize(first),const Size(348,204));
    expect(find.text('First synopsis'),findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(highlighted?.id,'b');
    expect(tester.getSize(first).width,132);
    expect(tester.getSize(second).width,348);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened?.id,'b');
    outside.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.getSize(second).width,132);
    expect(find.text('Second synopsis'),findsNothing);
    shelf.currentState!.focusRemembered();
    await tester.pumpAndSettle();
    expect(tester.getSize(second).width,348);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Leaving a row collapses it and vertical navigation moves to next row', (tester) async {
    final first=GlobalKey<CinemaShelfState>(), second=GlobalKey<CinemaShelfState>();
    const other=[Movie(id:'d',title:'Fourth')];
    await tester.pumpWidget(MaterialApp(theme:cinemaTheme(),home:Scaffold(
      body:SingleChildScrollView(child:Column(children:[
        CinemaShelf(key:first,title:'One',movies:movies,onHighlight:(_){},onOpen:(_){},
          onVertical:(down){if(down)second.currentState!.focusRemembered();}),
        CinemaShelf(key:second,title:'Two',movies:other,onHighlight:(_){},onOpen:(_){},
          onVertical:(down){if(!down)first.currentState!.focusRemembered();}),
      ])),
    )));
    first.currentState!.focusRemembered();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('size-a'))).width,132);
    expect(tester.getSize(find.byKey(const ValueKey('size-d'))).width,348);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('size-a'))).width,348);
    expect(tester.getSize(find.byKey(const ValueKey('size-d'))).width,132);
    expect(tester.takeException(),isNull);
  });

  test('Metadata uses available fields and does not invent missing values', () {
    final movie=Movie.fromJson({'id':'x','title':'Movie','year':2026,'genres':['Action','Drama'],'runtime':'100 min'});
    expect(movie.metadata,'Movie · Action, Drama · 2026 · 100 min');
    expect(Movie.fromJson({'id':'x','title':'Movie','year':null}).metadata,'Movie');
    expect(Movie.fromJson(movie.toJson()).metadata,movie.metadata);
  });
}
