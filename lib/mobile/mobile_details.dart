import 'package:flutter/material.dart';
import '../design.dart';
import '../engine.dart';
import '../next_episode.dart';
import '../series_page.dart' show distinctEpisodeTitle, episodeDateLabel;
import '../player.dart';
import 'mobile_library.dart';

class MobileDetails extends StatefulWidget {
  final Movie movie;
  final NativeEngine engine;
  final MobileLibrary library;
  const MobileDetails({super.key,required this.movie,required this.engine,required this.library});
  @override State<MobileDetails> createState()=>_MobileDetailsState();
}
class _MobileDetailsState extends State<MobileDetails>{
  List<Season> seasons=[];
  List<Episode> episodes=[];
  int? season;
  int revision=0;
  bool busy=false,opening=false;
  String? error;
  Movie get movie=>widget.movie;
  @override void initState(){super.initState();if(movie.episodic)loadSeasons();}
  Future<void> loadSeasons() async{
    final n=++revision;
    setState((){busy=true;error=null;});
    try{
      final data=await widget.engine.seasons(movie);
      if(!mounted||n!=revision)return;
      final previous=widget.library.resumeFor(movie);
      final wanted=previous==null?null:EpisodeIdentity.parse(previous)?.season;
      final chosen=data.where((s)=>s.number==wanted).firstOrNull??data.where((s)=>s.number>0).firstOrNull??data.firstOrNull;
      setState(()=>seasons=data);
      if(chosen!=null)await loadEpisodes(chosen.number);
      else setState(()=>busy=false);
    }catch(_){if(mounted&&n==revision)setState((){busy=false;error='Could not load seasons.';});}
  }
  Future<void> loadEpisodes(int number) async{
    final n=++revision;
    setState((){season=number;episodes=[];busy=true;error=null;});
    try{
      final data=await widget.engine.episodes(movie,number);
      if(mounted&&n==revision)setState((){episodes=data;busy=false;});
    }catch(_){if(mounted&&n==revision)setState((){busy=false;error='Could not load episodes.';});}
  }
  Future<void> chooseSeason() async{
    final result=await showModalBottomSheet<int>(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(
      child:ListView(shrinkWrap:true,children:[
        const Padding(padding:EdgeInsets.all(16),child:Text('Seasons',style:TextStyle(fontSize:20,fontWeight:FontWeight.w700))),
        for(final s in seasons)ListTile(title:Text(s.name),selected:s.number==season,
          trailing:s.number==season?const Icon(Icons.check):null,onTap:()=>Navigator.pop(ctx,s.number)),
      ])));
    if(mounted&&result!=null&&result!=season)await loadEpisodes(result);
  }
  Future<void> play(Movie item) async{
    if(opening)return;
    setState(()=>opening=true);
    try{
      final resolved=await widget.engine.identifyMovie(item);
      if(!mounted)return;
      await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>CinemaPlayer(movie:resolved,engine:widget.engine,history:widget.library.history)));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Playback information is unavailable.')));
    }finally{if(mounted)setState(()=>opening=false);}
  }
  @override Widget build(BuildContext context){
    final resumed=widget.library.resumeFor(movie);
    final resumedId=resumed==null?null:EpisodeIdentity.parse(resumed);
    final playLabel=opening?'Opening…':resumed!=null?(resumedId==null?'Resume':'Resume S${resumedId.season} E${resumedId.episode}'):movie.episodic?'Play episode':'Watch now';
    final first=episodes.where((e)=>aired(e,DateTime.now())).firstOrNull;
    final playable=resumed??(movie.episodic?(first==null||season==null?null:episodeMovie(movie,season!,first)):movie);
    final landscape=MediaQuery.sizeOf(context).width>MediaQuery.sizeOf(context).height;
    return Scaffold(body:SafeArea(child:CustomScrollView(slivers:[
      SliverToBoxAdapter(child:Stack(children:[
        SizedBox(height:landscape?220:260,width:double.infinity,child:Stack(fit:StackFit.expand,children:[
          CinemaArt(movie.art,cacheWidth:960),
          const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0x55000000),Colors.transparent,CinemaColors.canvas],stops:[0,.40,1]))),
        ])),
        Positioned(top:8,left:8,child:IconButton.filledTonal(tooltip:'Back',onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.arrow_back))),
      ])),
      SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(movie.title,style:const TextStyle(fontSize:29,height:1.12,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),Text(movie.metadata,style:const TextStyle(fontSize:12,color:CinemaColors.muted)),
        const SizedBox(height:18),
        FilledButton.icon(onPressed:playable==null||opening?null:()=>play(playable),icon:const Icon(Icons.play_arrow),
          label:Text(playLabel),
          style:FilledButton.styleFrom(minimumSize:const Size(0,48))),
        const SizedBox(height:12),
        if(movie.description.isNotEmpty)Text(movie.description,style:const TextStyle(fontSize:14,height:1.5)),
        const SizedBox(height:8),
        if(movie.episodic)Row(children:[
          const Expanded(child:Text('Episodes',style:TextStyle(fontSize:20,fontWeight:FontWeight.w700))),
          if(seasons.isNotEmpty)TextButton.icon(onPressed:chooseSeason,icon:const Icon(Icons.expand_more),label:Text(seasons.where((s)=>s.number==season).firstOrNull?.name??'Season')),
        ]),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Row(children:[Expanded(child:Text(error!)),TextButton(onPressed:()=>season==null?loadSeasons():loadEpisodes(season!),child:const Text('Retry'))]),
        if(movie.episodic&&!busy&&error==null&&episodes.isEmpty)const Text('No episodes listed.',style:TextStyle(color:CinemaColors.muted)),
      ]))),
      if(movie.episodic&&season!=null)SliverPadding(padding:const EdgeInsets.fromLTRB(16,0,16,24),sliver:SliverList.builder(
        itemCount:episodes.length,itemBuilder:(ctx,i){
          final ep=episodes[i],item=episodeMovie(movie,season!,episodes[i]);
          final title=distinctEpisodeTitle(ep),progress=widget.library.fraction(item);
          final available=aired(ep,DateTime.now());
          return Column(children:[
            InkWell(borderRadius:BorderRadius.circular(8),onTap:available&&!opening?()=>play(item):null,child:Padding(
              padding:const EdgeInsets.symmetric(vertical:12),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                SizedBox(width:108,child:Column(children:[
                  AspectRatio(aspectRatio:16/9,child:ClipRRect(borderRadius:BorderRadius.circular(7),child:CinemaArt(item.art,cacheWidth:360))),
                  if(progress!=null)LinearProgressIndicator(value:progress,minHeight:3),
                ])),
                const SizedBox(width:12),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('EPISODE ${ep.number}',style:const TextStyle(fontSize:11,color:CinemaColors.accent,fontWeight:FontWeight.w600)),
                  if(title.isNotEmpty)Text(title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600)),
                  Text([if(ep.runtime>0)'${ep.runtime} min',if(!available)episodeDateLabel(ctx,ep.airDate),if(widget.library.history.position(item)>Duration.zero)'Resume'].join(' · '),style:const TextStyle(fontSize:11,color:CinemaColors.muted)),
                  if(ep.description.isNotEmpty)Text(ep.description,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,color:CinemaColors.muted)),
                ])),
                const SizedBox(width:6),Icon(available?Icons.play_circle_outline:Icons.schedule,color:CinemaColors.muted),
              ]))),
            const Divider(height:1,color:Color(0x22FFFFFF)),
          ]);
        })),
    ])));
  }
}
