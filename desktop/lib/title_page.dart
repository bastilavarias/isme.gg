import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';
import 'catalog.dart';
import 'cinema_scene.dart';
import 'episode_model.dart';
import 'native_engine.dart';

class DesktopTitlePage extends StatefulWidget{
  final Movie movie;
  final bool initialSaved;
  final DesktopCatalog catalog;
  final Future<void> Function() onSave;
  final Future<void> Function(String episode) onPlay;
  const DesktopTitlePage({super.key,required this.movie,required this.initialSaved,
    required this.catalog,required this.onSave,required this.onPlay});
  @override State<DesktopTitlePage> createState()=>_DesktopTitlePageState();
}
class _DesktopTitlePageState extends State<DesktopTitlePage>{
  late bool saved=widget.initialSaved;
  late Future<List<DesktopEpisode>> episodes=widget.movie.episodic?loadEpisodes():Future.value([]);
  int? season;
  bool saving=false;
  Future<List<DesktopEpisode>> loadEpisodes()async{
    final catalog=widget.catalog;
    if(catalog is CinemetaDesktopCatalog)return catalog.episodes(widget.movie);
    return [];
  }
  Future<void> save()async{
    if(saving)return;
    setState(()=>saving=true);
    try{await widget.onSave();if(mounted)setState(()=>saved=!saved);}
    finally{if(mounted)setState(()=>saving=false);}
  }
  @override Widget build(BuildContext context){
    final m=widget.movie,available=DesktopNativeEngine.available;
    return Scaffold(appBar:AppBar(title:const Text('isme.gg'),backgroundColor:CinemaColors.canvas),
      body:ListView(children:[
        CinemaScene(movie:m,saved:saved,onDetails:()=>Navigator.pop(context),
          onSave:()=>unawaited(save()),height:480,detailsLabel:'Back to library',
          onPlay:available&&!m.episodic?()=>unawaited(widget.onPlay('')):null),
        Padding(padding:const EdgeInsets.fromLTRB(32,12,32,32),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            if(!available)const Padding(padding:EdgeInsets.only(bottom:16),child:Text(
              'Online playback requires the native desktop engine.',style:TextStyle(color:CinemaColors.muted))),
            const Text('About this title',style:TextStyle(fontSize:22,fontWeight:FontWeight.w700)),
            const SizedBox(height:10),
            Text(m.description.isEmpty?'No description available.':m.description),
            if(m.episodic)...[
              const SizedBox(height:28),
              FutureBuilder<List<DesktopEpisode>>(future:episodes,builder:(context,snapshot){
                if(snapshot.connectionState!=ConnectionState.done)return const LinearProgressIndicator();
                if(snapshot.hasError)return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Text('Episodes unavailable'),TextButton(onPressed:()=>setState(()=>episodes=loadEpisodes()),child:const Text('Retry')),
                ]);
                final all=snapshot.data??[];
                if(all.isEmpty)return const Text('No episode information available.');
                final seasons=all.map((e)=>e.season).toSet().toList();
                final selected=seasons.contains(season)?season!:seasons.first;
                return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const Text('Episodes',style:TextStyle(fontSize:22,fontWeight:FontWeight.w700)),
                  const SizedBox(height:12),
                  DropdownButton<int>(value:selected,items:seasons.map((s)=>DropdownMenuItem(
                    value:s,child:Text('Season $s'))).toList(),onChanged:(s)=>setState(()=>season=s)),
                  for(final e in all.where((e)=>e.season==selected))ListTile(
                    leading:Text('${e.number}',style:const TextStyle(color:CinemaColors.muted)),
                    title:Text(e.title),trailing:const Icon(Icons.play_circle_outline),
                    enabled:available,onTap:available?()=>unawaited(widget.onPlay(e.id)):null),
                ]);
              }),
            ],
          ],
        )),
      ]));
  }
}
