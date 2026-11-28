import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/platform_pill.dart';
import 'package:ismegg/platform_badge_icons.dart';
import 'package:ismegg/platform_rail.dart';

void main(){
  test('all supported brand names and aliases match their existing logo keys',(){
    for(final brand in PlatformBrand.brands.skip(1)){
      expect(platformBrandForProvider(brand.name)?.key,brand.key);
      for(final alias in brand.aliases){
        expect(platformBrandForProvider(' ${alias.toUpperCase()} ')?.key,brand.key);
      }
    }
    expect(platformBrandForProvider('Paramount Plus Amazon Channel'),isNull);
    expect(platformBrandForProvider('All'),isNull);
    expect(platformBrandForProvider('Unknown service'),isNull);
  });
  testWidgets('all twelve badge icons decode as squares',(tester)async{
    await tester.runAsync(()async{
      for(final brand in PlatformBrand.brands.skip(1)){
        final bytes=bundledPlatformBadgeIcon(brand.key);
        expect(bytes,isNotNull,reason:brand.name);
        final codec=await ui.instantiateImageCodec(bytes!);
        final frame=await codec.getNextFrame();
        expect(frame.image.width,frame.image.height,reason:brand.name);
        frame.image.dispose();
        codec.dispose();
      }
    });
  });
  testWidgets('all supported providers render compact image pills on TV and mobile',(tester)async{
    for(final tv in [true,false]){
      for(final brand in PlatformBrand.brands.skip(1)){
        await tester.pumpWidget(MaterialApp(home:Center(child:ProviderLogoPill(
          key:ValueKey('${brand.key}:$tv'),provider:brand.name,country:'PH',tv:tv))));
        final image=find.byType(Image);
        expect(image,findsOneWidget,reason:brand.name);
        final size=tv?22.0:19.0;
        expect(tester.getSize(find.byType(ProviderLogoPill)),Size.square(size));
        expect(find.text(brand.name),findsNothing);
        expect(tester.takeException(),isNull);
      }
    }
  });
  testWidgets('unknown provider retains text fallback',(tester)async{
    await tester.pumpWidget(const MaterialApp(home:Center(child:ProviderLogoPill(
      provider:'Unknown service',country:'PH',tv:false))));
    expect(find.byType(Image),findsNothing);
    expect(find.text('Unknown service'),findsOneWidget);
  });
}
