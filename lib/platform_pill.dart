import 'package:flutter/material.dart';
import 'engine.dart';

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
        return IgnorePointer(child:Semantics(
          label:'Subscription availability in ${engine.providerCountry}: $provider. Data from JustWatch via TMDB.',
          child:Container(
            constraints:const BoxConstraints(maxWidth:99),
            padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
            decoration:BoxDecoration(color:const Color(0xCC101010),
              borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0x44FFFFFF),width:.5)),
            child:Text(provider,maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w600,height:1.15)),
          )));
      },
    ));
}
