import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/platform_pill.dart';

class FakeEngine extends NativeEngine {
  final calls=<Map<String,dynamic>>[];
  String? name='Disney+';
  @override Future<Map<String,dynamic>> json(String path,
      {Map<String,String>? query,Map<String,dynamic>? body}) async {
    calls.add({...?body});
    return {'provider':name??''};
  }
}

void main() {
  const movie=Movie(id:'imdb:tt1234567',title:'Example',tmdbId:123);
  test('cached catalog keeps movie IDs and freshness flags',(){
    final snapshot=CatalogSnapshot.fromJson({
      'items':[movie.toJson(),{'id':'','title':'Invalid'}],
      'cacheHit':true,'stale':true,
    });
    expect(snapshot.cacheHit,isTrue);
    expect(snapshot.stale,isTrue);
    expect(snapshot.movies.single.tmdbId,123);
    expect(snapshot.movies.single.id,movie.id);
  });
  test('provider lookup deduplicates within a region and invalidates on change',() async {
    final engine=FakeEngine();
    addTearDown(engine.dispose);
    final a=engine.providerFor(movie),b=engine.providerFor(movie);
    expect(identical(a,b),isTrue);
    expect(await a,'Disney+');
    expect(engine.calls.single['country'],'PH');
    expect(engine.calls.single['token'],'');
    engine.configureProviders('US','example-token');
    expect(await engine.providerFor(movie),'Disney+');
    expect(engine.calls.length,2);
    expect(engine.calls.last['country'],'US');
    expect(engine.calls.last['tmdbId'],123);
  });
  test('no platform data produces no pill',() async {
    final engine=FakeEngine()..name=null;
    addTearDown(engine.dispose);
    expect(await engine.providerFor(movie),isNull);
    expect(await engine.providerFor(const Movie(id:'manual',title:'Manual')),isNull);
    expect(engine.calls.length,1);
  });
  testWidgets('pill stays compact and disappears when data changes',(tester) async {
    final engine=FakeEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Align(
      alignment:Alignment.topLeft,child:PlatformPill(engine:engine,movie:movie)))));
    await tester.pumpAndSettle();
    expect(find.text('Disney+'),findsOneWidget);
    expect(tester.getSize(find.byType(PlatformPill)).width,lessThanOrEqualTo(99));
    engine.name=null;
    engine.configureProviders('US','');
    await tester.pumpAndSettle();
    expect(find.text('Disney+'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
