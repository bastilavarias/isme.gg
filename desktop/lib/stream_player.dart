import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';
import 'package:ismegg/playback_mascot.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_engine.dart';

class DesktopStreamPlayer extends StatefulWidget {
  final Movie movie;
  final SharedPreferences prefs;
  final String episode;
  const DesktopStreamPlayer({super.key,required this.movie,required this.prefs,this.episode=''});
  @override State<DesktopStreamPlayer> createState()=>_DesktopStreamPlayerState();
}
class _DesktopStreamPlayerState extends State<DesktopStreamPlayer>{
  late final Player player;
  late final VideoController video;
  DesktopNativeEngine? engine;
  Timer? poll;
  StreamSubscription<Duration>? progress;
  StreamSubscription<String>? errors;
  bool ready=false,polling=false,opening=false;
  int source=0,generation=0;
  String status='resolving';
  String message='Finding a compatible source';
  List<dynamic> sources=[];
  int peers=0,percent=0;
  int lastSaved=0;
  String get resumeKey=>'desktop.resume.${widget.movie.id}:${widget.episode}';
  @override void initState(){
    super.initState();
    player=Player();video=VideoController(player);
    errors=player.stream.error.listen((_){
      if(mounted&&ready)setState((){ready=false;status='error';message='Playback failed. Try another source.';});
    });
    progress=player.stream.position.listen((position){
      if(!ready||(position.inSeconds-lastSaved).abs()<10)return;
      lastSaved=position.inSeconds;
      unawaited(saveResume());
    });
    unawaited(begin(0));
  }
  Future<void> saveResume()async{
    final prefs=widget.prefs;
    final movie=widget.movie;
    final key=resumeKey;
    final episode=widget.episode;
    final position=lastSaved;
    final length=player.state.duration.inSeconds;
    try{
      final finished=length>0&&position>=length-30;
      await prefs.setInt(key,finished?0:position);
      final rows=prefs.getStringList('desktop.watched.v1')??[];
      final encoded=jsonEncode(movie.toJson());
      final remaining=rows.where((row){
        try{return (jsonDecode(row) as Map)['id']!=movie.id;}catch(_){return false;}
      });
      await prefs.setStringList('desktop.watched.v1',[
        if(!finished&&position>0)encoded,...remaining
      ].take(30).toList());
      if(episode.isNotEmpty&&!finished)await prefs.setString('desktop.lastEpisode.${movie.id}',episode);
    }catch(_){/* Playback must remain usable if local preferences fail. */}
  }
  Future<void> begin(int index)async{
    if(opening||polling)return;
    final gen=++generation;
    poll?.cancel();
    setState((){source=index;ready=false;opening=true;status='resolving';message='Finding a compatible source';});
    try{
      await player.stop();
      if(engine==null){
        engine=DesktopNativeEngine();
        await engine!.connect();
      }
      if(!mounted||gen!=generation)return;
      await engine!.request('/api/start',body:{'id':widget.movie.id,'title':widget.movie.title,
        'source':index,'episode':widget.episode});
      final started=DateTime.now();
      poll=Timer.periodic(const Duration(milliseconds:500),(_)async{
        if(polling||gen!=generation||!mounted)return;
        polling=true;
        try{
          final state=await engine!.request('/api/state');
          if(!mounted||gen!=generation)return;
          final current=state['status']?.toString()??'loading';
          setState((){
            status=current;message=state['message']?.toString()??'Preparing playback';
            sources=state['sources'] is List?state['sources'] as List:[];
            peers=(state['peers'] as num?)?.toInt()??0;
            percent=((state['progress'] as num?)?.toInt()??0).clamp(0,100).toInt();
          });
          if(current=='error'||DateTime.now().difference(started)>const Duration(minutes:2)){
            poll?.cancel();
            if(mounted&&gen==generation)setState((){status='error';message='Could not prepare this source. Retry or choose another.';});
          }else if(current=='ready'&&state['streamUrl'] is String){
            poll?.cancel();
            final uri=engine!.streamUri(state['streamUrl'] as String);
            await player.open(Media(uri.toString(),httpHeaders:engine!.headers),play:false).timeout(const Duration(seconds:45));
            if(!mounted||gen!=generation)return;
            final resume=widget.prefs.getInt(resumeKey)??0;
            if(resume>0)await player.seek(Duration(seconds:resume));
            lastSaved=resume;
            await player.play();
            if(mounted&&gen==generation)setState(()=>ready=true);
          }
        }catch(_){
          poll?.cancel();
          if(mounted&&gen==generation)setState((){status='error';message='The local engine could not prepare playback.';});
        }finally{polling=false;}
      });
    }catch(_){
      final old=engine;engine=null;await old?.close();
      if(mounted&&gen==generation)setState((){status='error';message='Native engine unavailable. Prepare the desktop engine first.';});
    }finally{if(mounted&&gen==generation)setState(()=>opening=false);}
  }
  @override void dispose(){
    generation++;poll?.cancel();
    if(ready){lastSaved=player.state.position.inSeconds;unawaited(saveResume());}
    unawaited(progress?.cancel());unawaited(errors?.cancel());
    final current=engine;
    unawaited(player.dispose().whenComplete(()async{await current?.close();}));
    super.dispose();
  }
  IsmePlaybackPose get pose=>switch(status){
    'resolving'=>IsmePlaybackPose.finding,
    'loading'=>IsmePlaybackPose.connecting,
    'buffering'=>IsmePlaybackPose.buffering,
    'error'=>IsmePlaybackPose.failed,
    _=>IsmePlaybackPose.starting,
  };
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:CinemaColors.black,
    appBar:AppBar(backgroundColor:CinemaColors.black,title:Text(widget.movie.title),
      actions:[if(sources.length>1)PopupMenuButton<int>(tooltip:'Choose source',onSelected:(i)=>unawaited(begin(i)),
        itemBuilder:(_)=>List.generate(sources.length,(i){
          final row=sources[i];
          final name=row is Map?row['name']?.toString()??'Source ${i+1}':'Source ${i+1}';
          return PopupMenuItem(value:i,child:SizedBox(width:300,child:Text(name,maxLines:2,overflow:TextOverflow.ellipsis)));
        }))]),
    body:ready?Video(controller:video):Center(child:SingleChildScrollView(child:Padding(
      padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
        PlaybackMascot(pose:pose,size:160),
        const SizedBox(height:20),
        Text(message,textAlign:TextAlign.center,style:Theme.of(context).textTheme.titleLarge),
        if(status!='error')...[
          const SizedBox(height:18),SizedBox(width:240,child:LinearProgressIndicator(
            value:percent>0?percent/100:null)),
          const SizedBox(height:12),Text('$peers peers',style:const TextStyle(color:CinemaColors.muted)),
        ],
        if(status=='error')...[
          const SizedBox(height:16),
          FilledButton(onPressed:opening?null:()=>unawaited(begin(source)),child:const Text('Retry')),
          if(source+1<sources.length)TextButton(onPressed:opening?null:()=>unawaited(begin(source+1)),child:const Text('Try next source')),
        ],
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Back to library')),
      ])))));
}
