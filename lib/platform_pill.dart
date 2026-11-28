import 'package:flutter/material.dart';
import 'engine.dart';
import 'platform_logos.dart';
import 'platform_rail.dart';

/// Match exact names and aliases shared with the platform rail.
PlatformBrand? platformBrandForProvider(String provider) {
  final name=provider.trim().toLowerCase();
  for(final brand in PlatformBrand.brands.skip(1)){
    if(brand.name.toLowerCase()==name||brand.aliases.contains(name))return brand;
  }
  return null;
}

/// Decorative only: does not change card size, hit targets, or remote focus.
class PlatformPill extends StatelessWidget {
  final NativeEngine engine;
  final Movie movie;
  const PlatformPill({super.key,required this.engine,required this.movie});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<int>(
    valueListenable:engine.providerRevision,
    builder:(_,revision,__)=>FutureBuilder<String?>(
      key:ValueKey('${movie.id}:$revision'),
      future:engine.providerFor(movie),
      builder:(_,snapshot){
        final provider=snapshot.data;
        if(provider==null||provider.isEmpty)return const SizedBox.shrink();
        return ProviderLogoPill(provider:provider,country:engine.providerCountry,tv:engine.tv);
      },
    ));
}

/// Reuses bundled platform artwork, so known badges need no image requests.
class ProviderLogoPill extends StatelessWidget {
  final String provider,country;
  final bool tv;
  const ProviderLogoPill({super.key,required this.provider,required this.country,required this.tv});
  static const _wordmarks={'netflix','disney','prime','crunchyroll','hulu','viu'};
  @override Widget build(BuildContext context){
    final brand=platformBrandForProvider(provider);
    final bytes=brand==null?null:bundledPlatformLogo(brand.key);
    final height=tv?18.0:15.0;
    Widget textFallback()=>Container(
      constraints:const BoxConstraints(maxWidth:99),
      padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
      decoration:BoxDecoration(color:const Color(0xCC101010),
        borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0x44FFFFFF),width:.5)),
      child:Text(provider,maxLines:1,overflow:TextOverflow.ellipsis,
        style:const TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w600,height:1.15)),
    );
    return IgnorePointer(child:Semantics(
      label:'Subscription availability in $country: $provider. Data from JustWatch via TMDB.',
      child:ExcludeSemantics(child:bytes==null||brand==null?textFallback():Container(
        height:height+4,
        constraints:const BoxConstraints(maxWidth:76),
        padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
        decoration:BoxDecoration(color:brand.color,borderRadius:BorderRadius.circular(20),
          border:Border.all(color:const Color(0x44FFFFFF),width:.5)),
        child:Image.memory(bytes,height:height,
          width:_wordmarks.contains(brand.key)?(tv?48:40):height,
          fit:BoxFit.contain,excludeFromSemantics:true,
          errorBuilder:(_,__,___)=>FittedBox(fit:BoxFit.scaleDown,child:textFallback())),
      )),
    ));
  }
}
