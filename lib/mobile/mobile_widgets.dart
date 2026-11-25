import 'package:flutter/material.dart';
import '../design.dart';
import '../engine.dart';
import '../platform_pill.dart';

class MobilePoster extends StatelessWidget{
  final Movie movie;
  final NativeEngine engine;
  final VoidCallback onTap;
  const MobilePoster({super.key,required this.movie,required this.engine,required this.onTap});
  @override Widget build(BuildContext context)=>Semantics(button:true,label:movie.title,child:Material(
    color:Colors.transparent,borderRadius:BorderRadius.circular(9),clipBehavior:Clip.antiAlias,
    child:InkWell(onTap:onTap,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(8),child:Stack(fit:StackFit.expand,children:[
        CinemaArt(movie.poster.isEmpty?movie.art:movie.poster,cacheWidth:360),
        Positioned(top:5,left:5,child:PlatformPill(engine:engine,movie:movie)),
      ]))),
      const SizedBox(height:5),
      Text(movie.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w500)),
    ]))));
}
class MobileGrid extends StatelessWidget{
  final List<Movie> movies;
  final NativeEngine engine;
  final ValueChanged<Movie> onOpen;
  final ScrollController? controller;
  const MobileGrid({super.key,required this.movies,required this.engine,required this.onOpen,this.controller});
  @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,box){
    final count=((box.maxWidth-32)/113).floor().clamp(2,7).toInt();
    return GridView.builder(key:PageStorageKey('mobile-grid-${controller==null?'collection':'search'}'),controller:controller,padding:const EdgeInsets.fromLTRB(16,8,16,24),
      gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:count,childAspectRatio:.60,crossAxisSpacing:10,mainAxisSpacing:12),
      itemCount:movies.length,itemBuilder:(_,i)=>MobilePoster(movie:movies[i],engine:engine,onTap:()=>onOpen(movies[i])));
  });
}
class MobileEmpty extends StatelessWidget{
  final String title,description;
  final VoidCallback? retry;
  const MobileEmpty(this.title,this.description,{super.key,this.retry});
  @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(
    mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.movie_outlined,color:CinemaColors.muted,size:36),const SizedBox(height:14),
      Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w600)),
      const SizedBox(height:8),Text(description,textAlign:TextAlign.center,style:const TextStyle(color:CinemaColors.muted)),
      if(retry!=null)TextButton(onPressed:retry,child:const Text('Try again')),
    ])));
}
