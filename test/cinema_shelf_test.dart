import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/cinema_shelf.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';

void main() {
  testWidgets('TV rail expands focused movie and retains fixed height', (tester) async {
    const movies = [
      Movie(id: 'a', title: 'First'),
      Movie(id: 'b', title: 'Second'),
      Movie(id: 'c', title: 'Third'),
    ];
    Movie? highlighted;
    Movie? opened;
    await tester.pumpWidget(MaterialApp(theme: cinemaTheme(), home: Scaffold(
      body: CinemaShelf(title: 'Trending', movies: movies,
        onHighlight: (movie) => highlighted = movie,
        onOpen: (movie) => opened = movie),
    )));
    final first = find.byKey(const ValueKey('size-a'));
    final second = find.byKey(const ValueKey('size-b'));
    expect(tester.getSize(first).width, 348);
    expect(tester.getSize(second).width, 132);
    final focus = find.descendant(of: second, matching: find.byType(FocusableActionDetector));
    tester.widget<FocusableActionDetector>(focus).focusNode?.requestFocus();
    // The detector owns its node when no external node is supplied.
    final childFocus = find.descendant(of: second, matching: find.byType(Focus));
    final stateContext = tester.element(childFocus.first);
    Focus.of(stateContext, scopeOk: true).requestFocus();
    await tester.pumpAndSettle();
    expect(highlighted?.id, 'b');
    expect(tester.getSize(first).width, 132);
    expect(tester.getSize(second), const Size(348, 204));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened?.id, 'b');
    expect(tester.takeException(), isNull);
  });
}
