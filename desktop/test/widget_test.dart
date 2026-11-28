import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg_desktop/catalog.dart';
import 'package:ismegg_desktop/main.dart';
import 'package:ismegg_desktop/cinema_scene.dart';
import 'package:ismegg_desktop/title_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCatalog implements DesktopCatalog{
  @override Future<List<Movie>> browse(DesktopPage page,{String query=''})async=>[
    Movie(id:'imdb:tt1234567',title:page==DesktopPage.series?'Series example':'Example film',year:'2026'),
  ];
  @override void close(){}
}
void main(){
  test('catalog validates identity, type, title, and secure artwork',(){
    final items=CinemetaDesktopCatalog.parseMetas([
      {'id':'tt1234567','type':'movie','name':'Example','poster':'http://example.org/image'},
      {'id':'invalid','type':'movie','name':'Invalid'},
      {'id':'tt1234568','type':'series','name':'Series'},
    ],'movie');
    expect(items.single.id,'imdb:tt1234567');
    expect(items.single.poster,isEmpty);
  });
  testWidgets('desktop navigation, detail, and local bookmarks survive resize',(tester)async{
    SharedPreferences.setMockInitialValues({});
    final prefs=await SharedPreferences.getInstance();
    tester.view.physicalSize=const Size(1280,800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DesktopApp(prefs:prefs,catalog:FakeCatalog()));
    await tester.pumpAndSettle();
    expect(find.text('Example film'),findsOneWidget);
    expect(find.byType(CinemaScene),findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton,'My List'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile,'My List'));
    await tester.pumpAndSettle();
    expect(find.text('Example film'),findsOneWidget);
    expect(prefs.getStringList('desktop.saved.v1'),hasLength(1));
    tester.view.physicalSize=const Size(720,600);
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    expect(find.text('Example film'),findsOneWidget);
    await tester.tap(find.byType(DesktopPoster));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopTitlePage),findsOneWidget);
    expect(find.text('In My List'),findsOneWidget);
    await tester.tap(find.text('Back to library'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopTitlePage),findsNothing);
  });
}
