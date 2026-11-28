import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/platform_pill.dart';
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
  testWidgets('all supported providers render compact image pills on TV and mobile',(tester)async{
    for(final tv in [true,false]){
      for(final brand in PlatformBrand.brands.skip(1)){
        await tester.pumpWidget(MaterialApp(home:Center(child:ProviderLogoPill(
          key:ValueKey('${brand.key}:$tv'),provider:brand.name,country:'PH',tv:tv))));
        final image=find.byType(Image);
        expect(image,findsOneWidget,reason:brand.name);
        expect(tester.getSize(find.byType(ProviderLogoPill)).height,lessThanOrEqualTo(22));
        expect(tester.getSize(find.byType(ProviderLogoPill)).width,lessThanOrEqualTo(76));
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
