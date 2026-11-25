import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'design.dart';
import 'engine.dart';

class CinemaPlayer extends StatefulWidget {
  final Movie movie;
  final NativeEngine engine;
  final History history;
  final String magnet;
  const CinemaPlayer({super.key, required this.movie, required this.engine, required this.history, this.magnet = ''});
  @override State<CinemaPlayer> createState() => _CinemaPlayerState();
}
class _CinemaPlayerState extends State<CinemaPlayer> with WidgetsBindingObserver {
  VideoPlayerController? player;
  bool closed=false, busy=true, controls=true, leaving=false;
  int generation=0, progress=0, source=0;
  String? error;
  List<Map<String,dynamic>> sources=[];
  Timer? hide, saveTimer;
  Future<void>? pending;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);start();}
  Future<void> start({int index=0}) async {
    final old=pending;
    final n=++generation;
    setState((){busy=true;error=null;progress=0;source=index;controls=true;});
    if(old!=null){try{await old;}catch(_){}}
    if(closed||n!=generation)return;
    final job=load(n,index);
    pending=job;
    await job;
    if(identical(pending,job))pending=null;
  }
  Future<void> load(int n,int index) async {
    final previous=player;player=null;
    if(previous!=null){await save(previous);await previous.dispose();}
    try{
      if(closed||n!=generation)return;
      await widget.engine.start(widget.movie,magnet:widget.magnet,source:index);
      final deadline=DateTime.now().add(const Duration(minutes:3));
      while(!closed&&n==generation){
        final state=await widget.engine.status();
        if(closed||n!=generation)return;
        final status=state['status'];
        if(state['sources'] is List) sources=(state['sources'] as List).whereType<Map<String,dynamic>>().toList();
        if(status=='error')throw StateError(state['error']?.toString()??'Could not open media');
        if(status=='ready'){
          final c=VideoPlayerController.networkUrl(widget.engine.url('/stream/video'),httpHeaders:widget.engine.headers);
          try{
            await c.initialize().timeout(const Duration(seconds:90));
            if(closed||n!=generation){await c.dispose();return;}
            final position=widget.magnet.isEmpty?widget.history.position(widget.movie):Duration.zero;
            if(position>Duration.zero&&position<c.value.duration)await c.seekTo(position);
            if(closed||n!=generation){await c.dispose();return;}
            await c.play();
            if(closed||n!=generation){await c.dispose();return;}
            setState((){player=c;busy=false;});
            saveTimer?.cancel();saveTimer=Timer.periodic(const Duration(seconds:15),(_){final current=player;if(current!=null)unawaited(save(current));});
            showControls();return;
          }catch(_){await c.dispose();rethrow;}
        }
        setState(()=>progress=((state['progress'] as num?)?.round()??0).clamp(0,100).toInt());
        if(DateTime.now().isAfter(deadline))throw StateError('Media did not become ready. Try another source.');
        await Future<void>.delayed(const Duration(milliseconds:850));
      }
    }catch(e){if(!closed&&n==generation)setState((){error=e.toString();busy=false;});}
  }
  Future<void> save(VideoPlayerController c) async {
    if(widget.magnet.isEmpty&&c.value.isInitialized){try{await widget.history.save(widget.movie,c.value.position,c.value.duration);}catch(_){}}
  }
  void showControls(){
    if(!mounted||closed)return;
    setState(()=>controls=true);hide?.cancel();
    if(player?.value.isPlaying==true)hide=Timer(const Duration(seconds:6),(){if(mounted&&!closed)setState(()=>controls=false);});
  }
  Future<void> toggle() async {final c=player;if(c==null)return;if(c.value.isPlaying){await c.pause();}else{await c.play();}showControls();}
  Future<void> seek(int seconds) async {
    final c=player;if(c==null)return;
    final target=(c.value.position.inMilliseconds+seconds*1000).clamp(0,c.value.duration.inMilliseconds).toInt();
    await c.seekTo(Duration(milliseconds:target));showControls();
  }
  Future<void> captions() async {
    final c=player;if(c==null)return;
    hide?.cancel();
    try {
      final tracks=await widget.engine.subtitles();if(!mounted||closed)return;
      final choice=await showDialog<int>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Subtitles'),children:[
        SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,-1),child:const Text('Off')),
        for(final track in tracks)SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,track['id'] as int),child:Text((track['label']??track['lang']??'Subtitle').toString()))
      ]));
      if(choice==null||closed||!identical(c,player))return;
      if(choice<0){await c.setClosedCaptionFile(null);}
      else{final text=await widget.engine.caption(choice);if(!closed&&identical(c,player))await c.setClosedCaptionFile(Future.value(WebVTTCaptionFile(text)));}
    }catch(e){if(mounted&&!closed)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Subtitles unavailable: $e')));}
    finally{showControls();}
  }
  Future<void> chooseSource() async {
    hide?.cancel();
    final index=await showDialog<int>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Playback source'),children:[
      for(final row in sources)SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,row['index'] as int),child:Text((row['name']??'Source').toString(),maxLines:2,overflow:TextOverflow.ellipsis))
    ]));
    if(index!=null&&!closed)await start(index:index);else showControls();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused||state==AppLifecycleState.inactive){final c=player;if(c!=null){unawaited(c.pause());unawaited(save(c));}}
  }
  Future<void> shutdown() async {
    if(closed)return;closed=true;generation++;hide?.cancel();saveTimer?.cancel();
    final c=player;player=null;
    if(c!=null){await save(c);await c.dispose();}
    // Cancel engine while a pending initialization/poll is in flight.
    try{await widget.engine.stop();}catch(_){}
    final job=pending;if(job!=null){try{await job;}catch(_){}}
    try{await widget.engine.stop();}catch(_){}
  }
  Future<void> leave() async {
    if(leaving)return;setState(()=>leaving=true);await shutdown();
    if(mounted)Navigator.of(context).pop();
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);unawaited(shutdown());super.dispose();}
  String clock(Duration d){final h=d.inHours,m=d.inMinutes.remainder(60).toString().padLeft(2,'0'),s=d.inSeconds.remainder(60).toString().padLeft(2,'0');return h>0?'$h:$m:$s':'$m:$s';}
  @override Widget build(BuildContext context){
    final c=player;
    return PopScope(canPop:leaving,onPopInvokedWithResult:(didPop,_) {if(!didPop)unawaited(leave());},
      child:Scaffold(backgroundColor:CinemaColors.black,body:SafeArea(child:Focus(
      autofocus:true,onKeyEvent:(node,event){
        if(event is! KeyDownEvent)return KeyEventResult.ignored;
        final key=event.logicalKey;
        if(key==LogicalKeyboardKey.mediaPlayPause){unawaited(toggle());return KeyEventResult.handled;}
        if(key==LogicalKeyboardKey.escape||key==LogicalKeyboardKey.goBack){unawaited(leave());return KeyEventResult.handled;}
        if(!controls&&(key==LogicalKeyboardKey.select||key==LogicalKeyboardKey.enter||key==LogicalKeyboardKey.arrowDown||key==LogicalKeyboardKey.arrowUp)){showControls();return KeyEventResult.handled;}
        if(!controls&&key==LogicalKeyboardKey.arrowLeft){unawaited(seek(-10));return KeyEventResult.handled;}
        if(!controls&&key==LogicalKeyboardKey.arrowRight){unawaited(seek(10));return KeyEventResult.handled;}
        if(controls)showControls();
        return KeyEventResult.ignored;
      },child:Stack(fit:StackFit.expand,children:[
        if(c!=null&&!leaving)GestureDetector(onTap:showControls,child:Center(child:AspectRatio(aspectRatio:c.value.aspectRatio,child:VideoPlayer(c)))),
        if(busy||leaving)Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const CircularProgressIndicator(),const SizedBox(height:18),Text(leaving?'Closing…':'$progress%',style:const TextStyle(fontSize:22))])),
        if(error!=null&&!leaving)Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(error!,textAlign:TextAlign.center),const SizedBox(height:16),FilledButton(autofocus:true,onPressed:()=>start(index:source),child:const Text('Retry')),
          if(sources.length>1)TextButton(onPressed:chooseSource,child:const Text('Other source'))
        ]))),
        if(c!=null&&!leaving)ValueListenableBuilder<VideoPlayerValue>(valueListenable:c,builder:(_,v,__)=>Stack(children:[
          if(v.hasError)Center(child:Text(v.errorDescription??'Playback error')),
          if(v.isBuffering&&!v.hasError)const Center(child:CircularProgressIndicator()),
          if(v.caption.text.isNotEmpty)Align(alignment:controls?const Alignment(0,.45):const Alignment(0,.84),child:Container(color:const Color(0xCC000000),padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),child:Text(v.caption.text,textAlign:TextAlign.center,style:TextStyle(fontSize:widget.engine.tv?24:17)))),
          if(controls)Positioned(left:0,right:0,bottom:0,child:Container(
            decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.black])),
            padding:EdgeInsets.all(widget.engine.tv?28:12),child:Column(mainAxisSize:MainAxisSize.min,children:[
              Row(children:[Text(clock(v.position)),Expanded(child:Slider(value:v.position.inMilliseconds.clamp(0,v.duration.inMilliseconds).toDouble(),max:v.duration.inMilliseconds>0?v.duration.inMilliseconds.toDouble():1,onChanged:(n){c.seekTo(Duration(milliseconds:n.round()));showControls();})),Text(clock(v.duration))]),
              Wrap(alignment:WrapAlignment.center,spacing:8,children:[
                IconButton(tooltip:'Back 10 seconds',onPressed:()=>seek(-10),icon:const Icon(Icons.replay_10)),
                IconButton(autofocus:true,tooltip:v.isPlaying?'Pause':'Play',onPressed:toggle,icon:Icon(v.isPlaying?Icons.pause:Icons.play_arrow)),
                IconButton(tooltip:'Forward 10 seconds',onPressed:()=>seek(10),icon:const Icon(Icons.forward_10)),
                IconButton(tooltip:'Subtitles',onPressed:captions,icon:const Icon(Icons.closed_caption)),
                if(sources.length>1)IconButton(tooltip:'Playback source',onPressed:chooseSource,icon:const Icon(Icons.tune))
              ])
            ])))
        ])),
        if(controls&&!leaving)Positioned(left:12,top:8,right:12,child:Row(children:[IconButton(tooltip:'Back',onPressed:leave,icon:const Icon(Icons.arrow_back)),Expanded(child:Text(widget.movie.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:20)))]))
      ])))));
  }
}
