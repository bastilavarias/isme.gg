import 'package:flutter/material.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';

/// Artwork is the stage; navigation and controls sit above it, never fake data.
class CinemaScene extends StatelessWidget{
  final Movie movie;
  final VoidCallback onDetails,onSave;
  final VoidCallback? onPlay;
  final bool saved;
  final Widget? footer;
  final String detailsLabel;
  final double height;
  const CinemaScene({super.key,required this.movie,required this.onDetails,
    required this.onSave,required this.saved,this.onPlay,this.footer,this.height=460,
    this.detailsLabel='Explore title'});
  @override Widget build(BuildContext context)=>SizedBox(height:height,child:Stack(
    fit:StackFit.expand,children:[
      AnimatedSwitcher(
        duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:320),
        layoutBuilder:(current,previous)=>Stack(fit:StackFit.expand,children:[...previous,if(current!=null)current]),
        child:CinemaArt(movie.art,key:ValueKey(movie.id),cacheWidth:1920),
      ),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
        begin:Alignment.centerLeft,end:Alignment.centerRight,stops:[0,.45,1],
        colors:[CinemaColors.canvas,Color(0xD911110F),Color(0x1511110F)]))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
        begin:Alignment.topCenter,end:Alignment.bottomCenter,stops:[.5,1],
        colors:[Colors.transparent,CinemaColors.canvas]))),
      LayoutBuilder(builder:(context,box)=>Align(alignment:Alignment.bottomLeft,child:Padding(
        padding:const EdgeInsets.fromLTRB(32,24,24,32),child:ConstrainedBox(
          constraints:BoxConstraints(maxWidth:box.maxWidth<680?(box.maxWidth-56).clamp(0.0,520.0).toDouble():520),
          child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(movie.type,style:const TextStyle(color:CinemaColors.accent,fontWeight:FontWeight.w600)),
            const SizedBox(height:8),
            Text(movie.title,maxLines:2,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontSize:box.maxWidth<680?32:box.maxWidth>1250?58:48,height:1.07,fontWeight:FontWeight.w800)),
            const SizedBox(height:12),
            Text([movie.year,movie.genre,if(movie.rating.isNotEmpty)'IMDb ${movie.rating}']
              .where((v)=>v.isNotEmpty).join('  |  '),maxLines:2,overflow:TextOverflow.ellipsis,
              style:const TextStyle(color:CinemaColors.muted)),
            if(movie.description.isNotEmpty)...[
              const SizedBox(height:14),
              Text(movie.description,maxLines:box.maxWidth<680?2:3,overflow:TextOverflow.ellipsis,
                style:const TextStyle(fontSize:14,height:1.6)),
            ],
            const SizedBox(height:22),
            Wrap(spacing:10,runSpacing:8,children:[
              FilledButton.icon(onPressed:onPlay??onDetails,icon:Icon(onPlay==null?Icons.info_outline:Icons.play_arrow),
                label:Text(onPlay==null?detailsLabel:'Watch now')),
              OutlinedButton.icon(onPressed:onSave,icon:Icon(saved?Icons.check:Icons.add),
                label:Text(saved?'In My List':'My List')),
              if(onPlay!=null)IconButton(tooltip:'Details',onPressed:onDetails,icon:const Icon(Icons.info_outline)),
            ]),
            if(footer!=null)...[const SizedBox(height:14),footer!],
          ])),
        ),
      ))),
    ]));
}

class CinemaShelf extends StatefulWidget{
  final String title;
  final List<Movie> movies;
  final Widget Function(Movie) poster;
  const CinemaShelf({super.key,required this.title,required this.movies,required this.poster});
  @override State<CinemaShelf> createState()=>_CinemaShelfState();
}
class _CinemaShelfState extends State<CinemaShelf>{
  final scroll=ScrollController();
  void move(int direction){
    if(!scroll.hasClients)return;
    final next=(scroll.offset+direction*scroll.position.viewportDimension*.83)
      .clamp(0.0,scroll.position.maxScrollExtent).toDouble();
    if(MediaQuery.disableAnimationsOf(context)){scroll.jumpTo(next);}
    else{scroll.animateTo(next,duration:const Duration(milliseconds:240),curve:Curves.easeOutCubic);}
  }
  @override void dispose(){scroll.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    if(widget.movies.isEmpty)return const SizedBox.shrink();
    return Padding(padding:const EdgeInsets.fromLTRB(32,6,24,26),
      child:LayoutBuilder(builder:(context,box){
        final width=(box.maxWidth/6.4).clamp(164.0,244.0).toDouble();
        final canScroll=widget.movies.length*(width+16)>box.maxWidth;
        return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(widget.title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w700))),
            if(canScroll)...[
              IconButton(tooltip:'Previous titles',onPressed:()=>move(-1),icon:const Icon(Icons.chevron_left)),
              IconButton(tooltip:'More titles',onPressed:()=>move(1),icon:const Icon(Icons.chevron_right)),
            ],
          ]),
          const SizedBox(height:10),
          SizedBox(height:width*1.5+52,child:ListView.separated(
            controller:scroll,scrollDirection:Axis.horizontal,itemCount:widget.movies.length,
            separatorBuilder:(_,__)=>const SizedBox(width:16),
            itemBuilder:(_,i)=>SizedBox(width:width,child:widget.poster(widget.movies[i])),
          )),
        ]);
      }));
  }
}
