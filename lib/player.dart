import 'dart:async';
import 'package:flutter/foundation.dart';
import 'playback_recovery.dart';
import 'player_preferences.dart';
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
  bool closed=false, busy=true, controls=true, leaving=false, wantsPlayback=true;
  int generation=0, progress=0, source=0;
  String? error;
  String phase='Starting', lastFault='none';
  bool diagnostics=false;
  Map<String,dynamic> audio={}, nativeState={};
  final RecoveryBudget recovery=RecoveryBudget();
  Duration resume=Duration.zero, lastPosition=Duration.zero;
  DateTime lastAdvance=DateTime.now();
  List<Map<String,dynamic>> sources=[];
  Timer? hide, saveTimer, watchdog;
  Future<void>? pending;
  Completer<void>? cancellation;
  int? captionId;
  int subtitleRevision=0;
  bool settingsOpen=false;
  String? audioChoice, recommendedAudioId;
  int audioRevision=0;
  List<VideoAudioTrack> audioTracks=[];
  final FocusNode playerFocus=FocusNode(debugLabel:'Cinema player');
  final FocusNode playFocus=FocusNode(debugLabel:'Play or pause');
  String get subtitleLanguage=>widget.history.prefs.getString('isme-subtitle-language')??'eng';
  @override void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    resume=widget.magnet.isEmpty?widget.history.position(widget.movie):Duration.zero;
    HardwareKeyboard.instance.addHandler(fallbackRemote);
    unawaited(start());
  }
  bool active(int n)=>mounted&&!closed&&n==generation;
  void cancelAttempt(){
    final c=cancellation;
    if(c!=null&&!c.isCompleted)c.complete();
  }
  Future<T> cancellable<T>(Future<T> task, Completer<void> cancel) => Future.any<T>([
    task, cancel.future.then<T>((_)=>throw const PlaybackFailure(PlaybackFault.internal,'Playback cancelled'))
  ]);
  void rememberPosition(VideoPlayerController c){
    final v=c.value;
    if(v.isInitialized&&!v.hasError)resume=v.position;
    else if(lastPosition>Duration.zero)resume=lastPosition;
  }
  int? nextSource(PlaybackFault fault)=>recovery.next(current:source,fault:fault,
    candidates:sources.map((row)=>row['index']).whereType<int>(),manualSource:widget.magnet.isNotEmpty);
  void logFault(Object e){
    lastFault=classifyPlaybackError(e).name;
    if(kDebugMode)debugPrint('IsmePlayback: phase=$phase category=$lastFault attempt=${recovery.total}');
  }
  Future<void> start({int index=0,bool resetBudget=true}) async {
    if(closed||!mounted)return;
    final old=pending;
    final n=++generation;
    cancelAttempt();subtitleRevision++;audioRevision++;recommendedAudioId=null;audioTracks=[];watchdog?.cancel();saveTimer?.cancel();hide?.cancel();
    if(resetBudget){recovery.reset();lastFault='none';wantsPlayback=true;}
    setState((){busy=true;error=null;progress=0;source=index;controls=true;phase='Opening media';});
    if(old!=null){
      try{await widget.engine.stop();}catch(_){}
      try{await old;}catch(_){}
    }
    if(!active(n))return;
    final cancel=Completer<void>();cancellation=cancel;
    final job=load(n,index,cancel);
    pending=job;
    await job;
    if(identical(pending,job))pending=null;
  }
  Future<void> load(int n,int index,Completer<void> cancel) async {
    final previous=player;
    if(previous!=null){
      rememberPosition(previous);
      if(active(n))setState(()=>player=null);else player=null;
      await save(previous);await previous.dispose();
    }
    var candidate=index;
    final overall=DateTime.now().add(const Duration(minutes:4));
    while(active(n)){
      recovery.record(candidate);
      setState((){source=candidate;phase='Preparing media';progress=0;});
      try{
        await attempt(n,candidate,cancel,overall);
        return;
      }catch(e){
        if(!active(n))return;
        logFault(e);
        final next=DateTime.now().isBefore(overall)?nextSource(classifyPlaybackError(e)):null;
        if(next==null){
          try{await widget.engine.stop();}catch(_){}
          if(active(n))setState((){error='Unable to play this media after ${recovery.total} attempt(s). Retry or choose another source.';busy=false;phase='Stopped';});
          return;
        }
        candidate=next;
        setState(()=>phase='Recovering playback');
        await Future<void>.delayed(const Duration(milliseconds:500));
      }
    }
  }
  Future<void> attempt(int n,int index,Completer<void> cancel,DateTime overall) async {
    final deadline=DateTime.now().add(const Duration(seconds:65));
    await widget.engine.start(widget.movie,magnet:widget.magnet,source:index);
    while(active(n)){
      if(DateTime.now().isAfter(deadline)||DateTime.now().isAfter(overall))throw const PlaybackFailure(PlaybackFault.transient,'Media readiness deadline exceeded');
      final state=await cancellable(widget.engine.status(),cancel);
      if(!active(n))return;
      nativeState=state;
      final status=state['status'];
      if(state['sources'] is List && (state['sources'] as List).isNotEmpty) sources=(state['sources'] as List).whereType<Map<String,dynamic>>().toList();
      if(status=='error')throw StateError(state['error']?.toString()??'Could not open media');
      if(status=='ready'){
        setState(()=>phase='Validating stream');
        final path=state['streamUrl'] as String?;
        if(path==null||!path.startsWith('/stream/video'))throw const PlaybackFailure(PlaybackFault.internal,'Invalid media endpoint');
        final uri=widget.engine.url(path);
        await cancellable(widget.engine.probe(uri),cancel);
        if(!active(n))return;
        setState(()=>phase='Initializing player');
        final c=VideoPlayerController.networkUrl(uri,httpHeaders:widget.engine.headers);
        bool adopted=false;
        try{
          await cancellable(c.initialize().timeout(const Duration(seconds:45)),cancel);
          if(!active(n))return;
          if(resume>Duration.zero&&resume<c.value.duration)await cancellable(c.seekTo(resume),cancel);
          if(!active(n))return;
          // Subtitle discovery and audio preference are applied after adoption; neither blocks startup.
          if(!active(n))return;
          if(wantsPlayback)await cancellable(c.play(),cancel);
          if(!active(n))return;
          setState((){player=c;busy=false;phase='Playing';});
          adopted=true;
          lastPosition=c.value.position;lastAdvance=DateTime.now();
          saveTimer=Timer.periodic(const Duration(seconds:15),(_){final current=player;if(current!=null)unawaited(save(current));});
          watchdog=Timer.periodic(const Duration(seconds:2),(_)=>monitor(c,n));
          showControls(focus:true);
          unawaited(autoSubtitles(c,n));
          unawaited(applyAudioPreference(c,n));
          return;
        }finally{if(!adopted)await c.dispose();}
      }
      setState(()=>progress=((state['progress'] as num?)?.round()??0).clamp(0,100).toInt());
      await cancellable(Future<void>.delayed(const Duration(milliseconds:850)),cancel);
    }
  }
  void monitor(VideoPlayerController c,int n){
    if(!active(n)||!identical(player,c)||busy)return;
    final v=c.value;
    if(v.hasError){
      recoverRuntime(v.errorDescription??'Playback error');return;
    }
    if(v.position!=lastPosition){lastPosition=v.position;resume=v.position;lastAdvance=DateTime.now();}
    if(v.isCompleted){wantsPlayback=false;lastAdvance=DateTime.now();return;}
    if(!wantsPlayback){lastAdvance=DateTime.now();return;}
    if(DateTime.now().difference(lastAdvance)>const Duration(seconds:40)){
      recoverRuntime(const PlaybackFailure(PlaybackFault.transient,'Playback stalled'));
    }
  }
  void recoverRuntime(Object failure){
    if(closed||busy)return;
    watchdog?.cancel();logFault(failure);
    final next=nextSource(classifyPlaybackError(failure));
    if(next!=null){unawaited(start(index:next,resetBudget:false));return;}
    final job=stopAfterFailure();
    pending=job;
    unawaited(job.whenComplete((){if(identical(pending,job))pending=null;}));
  }
  Future<void> stopAfterFailure() async {
    if(closed||!mounted)return;
    final n=++generation;cancelAttempt();saveTimer?.cancel();hide?.cancel();
    final c=player;
    setState((){player=null;busy=true;phase='Stopping';});
    if(c!=null){rememberPosition(c);await save(c);await c.dispose();}
    try{await widget.engine.stop();}catch(_){}
    if(active(n))setState((){busy=false;controls=true;phase='Stopped';error='Playback could not recover. Retry or choose another source.';});
  }
  Future<void> showDiagnostics() async {
    if(!kDebugMode)return;
    setState(()=>diagnostics=!diagnostics);
    if(diagnostics){
      try{final data=await widget.engine.audioDiagnostics();if(mounted&&!closed)setState(()=>audio=data);}catch(_){}
    }
  }
  Future<void> save(VideoPlayerController c) async {
    if(widget.magnet.isEmpty&&c.value.isInitialized){try{await widget.history.save(widget.movie,c.value.position,c.value.duration);}catch(_){}}
  }
  void armControlsTimer(){
    hide?.cancel();
    if(!closed&&!settingsOpen&&controls&&player?.value.isPlaying==true){
      hide=Timer(const Duration(seconds:6),(){
        if(!mounted||closed||settingsOpen||player?.value.isPlaying!=true)return;
        // Keep a focus target mounted even when every control is hidden.
        playerFocus.requestFocus();
        setState(()=>controls=false);
      });
    }
  }
  void showControls({bool focus=false}){
    if(!mounted||closed||leaving)return;
    final reveal=!controls;
    if(reveal)setState(()=>controls=true);
    if((reveal||focus)&&player!=null&&!settingsOpen){
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted&&!closed&&controls&&!settingsOpen&&playFocus.context!=null)playFocus.requestFocus();
      });
    }
    armControlsTimer();
  }
  bool get currentRoute=>mounted&&!closed&&!leaving&&ModalRoute.of(context)?.isCurrent==true;
  bool fallbackRemote(KeyEvent event){
    if(!currentRoute||settingsOpen)return false;
    if(event is KeyDownEvent||event is KeyRepeatEvent){
      // Descendant shortcuts can consume directional keys before the parent
      // receives them. Renew visibility independently, without consuming them.
      if(controls)armControlsTimer();
      if(!playerFocus.hasFocus){
        playerFocus.requestFocus();
        if(controls){showControls(focus:true);return false;}
        return handleRemote(event)==KeyEventResult.handled;
      }
    }
    return false;
  }
  KeyEventResult handleRemote(KeyEvent event){
    if(!currentRoute||settingsOpen)return KeyEventResult.ignored;
    if(event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    final key=event.logicalKey;
    final repeat=event is KeyRepeatEvent;
    if(key==LogicalKeyboardKey.escape||key==LogicalKeyboardKey.goBack){
      if(!repeat)unawaited(leave());return KeyEventResult.handled;
    }
    if(key==LogicalKeyboardKey.mediaPlayPause||key==LogicalKeyboardKey.mediaPlay||
        key==LogicalKeyboardKey.mediaPause||key==LogicalKeyboardKey.space){
      if(!repeat){
        if(key==LogicalKeyboardKey.mediaPlay){unawaited(setPlaying(true));}
        else if(key==LogicalKeyboardKey.mediaPause){unawaited(setPlaying(false));}
        else{unawaited(toggle());}
      }
      return KeyEventResult.handled;
    }
    if(key==LogicalKeyboardKey.mediaFastForward||key==LogicalKeyboardKey.mediaRewind){
      unawaited(seek(key==LogicalKeyboardKey.mediaFastForward?10:-10));
      return KeyEventResult.handled;
    }
    if(!controls){
      if(key==LogicalKeyboardKey.arrowLeft||key==LogicalKeyboardKey.arrowRight){
        unawaited(seek(key==LogicalKeyboardKey.arrowRight?10:-10));return KeyEventResult.handled;
      }
      if(key==LogicalKeyboardKey.select||key==LogicalKeyboardKey.enter||
          key==LogicalKeyboardKey.arrowDown||key==LogicalKeyboardKey.arrowUp){
        showControls(focus:true);return KeyEventResult.handled;
      }
    }
    if(controls)armControlsTimer();
    return KeyEventResult.ignored;
  }
  Future<void> setPlaying(bool value) async{
    final c=player;if(c==null||closed||busy)return;
    wantsPlayback=value;lastAdvance=DateTime.now();
    try{
      if(value){if(c.value.isCompleted)await c.seekTo(Duration.zero);await c.play();}
      else{await c.pause();}
    }catch(e){if(identical(c,player)&&!closed)recoverRuntime(e);}
    if(identical(c,player))showControls();
  }
  Future<void> toggle() => setPlaying(!wantsPlayback);
  Future<void> seek(int seconds) async {
    final c=player;if(c==null||closed||busy)return;
    final target=(c.value.position.inMilliseconds+seconds*1000).clamp(0,c.value.duration.inMilliseconds).toInt();
    lastAdvance=DateTime.now();
    showControls();
    try{await c.seekTo(Duration(milliseconds:target));}
    catch(e){if(!closed&&identical(c,player))recoverRuntime(e);}
  }
  bool samePlayer(VideoPlayerController c,int n)=>active(n)&&identical(c,player);
  Future<void> autoSubtitles(VideoPlayerController c,int n) async{
    final revision=++subtitleRevision;
    captionId=null;
    final language=subtitleLanguage;
    if(language=='off'||widget.magnet.isNotEmpty)return;
    bool valid()=>samePlayer(c,n)&&revision==subtitleRevision;
    try{
      final tracks=await widget.engine.subtitles();
      if(!valid())return;
      for(final track in subtitleCandidates(tracks,language).take(3)){
        try{
          final id=track['id'] as int;
          final raw=await widget.engine.caption(id);
          if(!valid())return;
          final captions=WebVTTCaptionFile(raw);
          await c.setClosedCaptionFile(Future.value(captions));
          if(valid())setState(()=>captionId=id);
          return;
        }catch(_){if(!valid())return;}
      }
    }catch(_){if(kDebugMode)debugPrint('IsmePlayback: auto subtitles unavailable');}
  }
  void notice(String message){
    if(mounted&&!closed)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }
  Future<T?> settingsDialog<T>(WidgetBuilder builder) async{
    if(settingsOpen||!currentRoute)return null;
    settingsOpen=true;hide?.cancel();
    try{return await showDialog<T>(context:context,builder:(ctx)=>Shortcuts(shortcuts:const {SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),SingleActivator(LogicalKeyboardKey.enter):ActivateIntent()},child:builder(ctx)));}
    finally{settingsOpen=false;if(mounted&&!closed&&currentRoute)showControls(focus:true);}
  }
  Future<void> captions() async {
    final c=player;final n=generation;if(c==null||settingsOpen)return;
    hide?.cancel();
    // Show a focusable menu immediately, while provider discovery runs.
    final tracksFuture=widget.engine.subtitles();
    try {
      final choice=await settingsDialog<Map<String,dynamic>>((ctx)=>SimpleDialog(
        title:const Text('Subtitles'),children:[
          TextButton(autofocus:true,onPressed:()=>Navigator.pop(ctx,{'id':-1,'lang':'off'}),child:Text(captionId==null?'Off (no active track)':'Off')),
          FutureBuilder<List<Map<String,dynamic>>>(future:tracksFuture,builder:(_,snapshot){
            if(snapshot.hasError)return const Padding(padding:EdgeInsets.all(16),child:Text('Subtitles unavailable'));
            if(!snapshot.hasData)return const Padding(padding:EdgeInsets.all(16),child:LinearProgressIndicator());
            final tracks=snapshot.data!;
            if(tracks.isEmpty)return const Padding(padding:EdgeInsets.all(16),child:Text('No external subtitles found'));
            return SizedBox(width:420,child:ConstrainedBox(constraints:const BoxConstraints(maxHeight:300),child:ListView(
              shrinkWrap:true,children:[
                for(final track in tracks.take(60)) TextButton(onPressed:()=>Navigator.pop(ctx,track),
                  child:Text('${track['label']??track['lang']??'Subtitle'} — ${track['name']??''}${track['id']==captionId?' (selected)':''}',maxLines:2,overflow:TextOverflow.ellipsis))
              ])));
          })
        ]));
      if(choice==null||!samePlayer(c,n))return;
      final revision=++subtitleRevision;
      final id=choice['id'] as int;
      if(id<0){
        await c.setClosedCaptionFile(null);
        if(samePlayer(c,n)&&revision==subtitleRevision){
          setState(()=>captionId=null);
          await widget.history.prefs.setString('isme-subtitle-language','off');
        }
      }else{
        final raw=await widget.engine.caption(id);
        if(!samePlayer(c,n)||revision!=subtitleRevision)return;
        await c.setClosedCaptionFile(Future.value(WebVTTCaptionFile(raw)));
        if(samePlayer(c,n)&&revision==subtitleRevision){
          setState(()=>captionId=id);
          await widget.history.prefs.setString('isme-subtitle-language',choice['lang']?.toString()??'eng');
        }
      }
    }catch(_){if(samePlayer(c,n))notice('Subtitles unavailable.');}
    finally{if(samePlayer(c,n))showControls();}
  }
  Future<void> applyAudioPreference(VideoPlayerController c,int n) async{
    if(!samePlayer(c,n))return;
    final revision=++audioRevision;
    bool valid()=>samePlayer(c,n)&&revision==audioRevision;
    try{
      if(!c.isAudioTrackSupportAvailable())return;
      final tracks=await c.getAudioTracks();
      if(!valid())return;
      recommendedAudioId=compatibleAudioTrack(tracks)?.id;
      // IDs belong to the current media instance. Preserve a manual
      // preference using metadata rather than assuming an old ID is valid.
      final chosen=tracks.where((t)=>audioTrackLabel(t)==audioChoice).firstOrNull??compatibleAudioTrack(tracks);
      if(chosen!=null&&!chosen.isSelected&&!settingsOpen){
        await c.selectAudioTrack(chosen.id);
      }
      if(!valid())return;
      final refreshed=await c.getAudioTracks();
      if(valid())setState(()=>audioTracks=refreshed);
    }catch(_){if(kDebugMode)debugPrint('IsmePlayback: audio track discovery unavailable');}
  }
  Future<void> chooseAudio() async{
    final c=player;final n=generation;if(c==null||settingsOpen)return;
    if(!c.isAudioTrackSupportAvailable()){notice('Audio track selection is unavailable on this device.');return;}
    final revision=++audioRevision;
    final tracksFuture=c.getAudioTracks();
    try{
      final choice=await settingsDialog<String>((ctx)=>SimpleDialog(
        title:const Text('Audio tracks'),children:[
          const Padding(padding:EdgeInsets.fromLTRB(20,0,20,8),child:Text('Choose an audio track already included in the video.')),
          FutureBuilder<List<VideoAudioTrack>>(future:tracksFuture,builder:(_,snapshot){
            if(snapshot.hasError)return const Padding(padding:EdgeInsets.all(16),child:Text('Could not read audio tracks.'));
            if(!snapshot.hasData)return const Padding(padding:EdgeInsets.all(16),child:LinearProgressIndicator());
            final tracks=snapshot.data!;
            if(tracks.isEmpty)return const Padding(padding:EdgeInsets.all(16),child:Text('No selectable audio tracks.'));
            return SizedBox(width:420,child:ConstrainedBox(constraints:const BoxConstraints(maxHeight:300),child:ListView(shrinkWrap:true,children:[
              TextButton(autofocus:audioChoice==null,onPressed:()=>Navigator.pop(ctx,''),child:Text(audioChoice==null?'Automatic preference (active)':'Automatic preference')),
              for(final track in tracks)TextButton(autofocus:audioChoice!=null&&track.isSelected,onPressed:()=>Navigator.pop(ctx,track.id),
                child:Text('${audioTrackLabel(track).isEmpty?'Audio track ${tracks.indexOf(track)+1}':audioTrackLabel(track)}${track.isSelected?' (selected)':''}'))
            ])));
          }),
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))
        ]));
      if(choice==null||!samePlayer(c,n)||revision!=audioRevision)return;
      final available=await tracksFuture;
      if(!samePlayer(c,n)||revision!=audioRevision)return;
      final picked=choice.isEmpty?(available.where((t)=>t.id==recommendedAudioId).firstOrNull??compatibleAudioTrack(available)):available.where((t)=>t.id==choice).firstOrNull;
      if(picked==null)return;
      if(!picked.isSelected)await c.selectAudioTrack(picked.id);
      if(!samePlayer(c,n)||revision!=audioRevision)return;
      audioChoice=choice.isEmpty?null:audioTrackLabel(picked);
      final tracks=await c.getAudioTracks();
      if(samePlayer(c,n)&&revision==audioRevision)setState(()=>audioTracks=tracks);
    }catch(_){if(samePlayer(c,n))notice('Could not switch audio track.');}
    finally{if(samePlayer(c,n))showControls();}
  }
  Future<void> chooseSource() async {
    final index=await settingsDialog<int>((ctx)=>SimpleDialog(title:const Text('Playback source'),children:[
      for(final row in sources)TextButton(autofocus:row['index']==source,onPressed:()=>Navigator.pop(ctx,row['index'] as int),child:Text((row['name']??'Source').toString(),maxLines:2,overflow:TextOverflow.ellipsis))
    ]));
    if(index!=null&&!closed)await start(index:index);else showControls();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused||state==AppLifecycleState.inactive){wantsPlayback=false;final c=player;if(c!=null){unawaited(c.pause());unawaited(save(c));}}
  }
  Future<void> shutdown() async {
    if(closed)return;closed=true;generation++;subtitleRevision++;cancelAttempt();hide?.cancel();saveTimer?.cancel();watchdog?.cancel();
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
  @override void dispose(){HardwareKeyboard.instance.removeHandler(fallbackRemote);WidgetsBinding.instance.removeObserver(this);unawaited(shutdown());playerFocus.dispose();playFocus.dispose();super.dispose();}
  String clock(Duration d){final h=d.inHours,m=d.inMinutes.remainder(60).toString().padLeft(2,'0'),s=d.inSeconds.remainder(60).toString().padLeft(2,'0');return h>0?'$h:$m:$s':'$m:$s';}
  Widget diagnosticsPanel(VideoPlayerValue? v){
    final position=v?.position??resume;
    final buffered=v?.buffered.where((r)=>r.start<=position&&r.end>=position).fold<int>(0,(max,r){
      final ms=(r.end-position).inMilliseconds;return ms>max?ms:max;
    })??0;
    final rows=<String,String>{
      'Phase':phase,'Attempts':'${recovery.total}/${RecoveryBudget.maxAttempts}',
      'Last error':lastFault,'Engine':nativeState['status']?.toString()??'—',
      'Resolution':v==null?'—':'${v.size.width.round()} × ${v.size.height.round()}',
      'Buffer ahead':'${(buffered/1000).toStringAsFixed(1)} s',
      'Output sample rate':audio['sampleRate']?.toString()??'Unavailable',
      'Output frames/buffer':audio['framesPerBuffer']?.toString()??'Unavailable',
      'Audio track':audioTracks.where((t)=>t.isSelected).map(audioTrackLabel).firstOrNull??'Unavailable',
      'Audio underruns':'See Logcat',
    };
    return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Playback diagnostics',style:TextStyle(fontWeight:FontWeight.bold)),
      for(final row in rows.entries) Padding(padding:const EdgeInsets.only(top:4),
        child:Text('${row.key}: ${row.value}',style:const TextStyle(fontSize:12)))
    ]);
  }
  @override Widget build(BuildContext context){
    final c=player;
    return PopScope(canPop:leaving,onPopInvokedWithResult:(didPop,_) {if(!didPop)unawaited(leave());},
      child:Scaffold(backgroundColor:CinemaColors.black,body:SafeArea(child:Focus(
      focusNode:playerFocus,autofocus:true,onKeyEvent:(_,event)=>handleRemote(event),
      child:Shortcuts(shortcuts:const {SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),SingleActivator(LogicalKeyboardKey.enter):ActivateIntent()},child:Stack(fit:StackFit.expand,children:[
        if(c!=null&&!leaving)GestureDetector(onTap:showControls,child:Center(child:AspectRatio(aspectRatio:c.value.aspectRatio,child:VideoPlayer(c)))),
        if(busy||leaving)Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const CircularProgressIndicator(),const SizedBox(height:18),Text(leaving?'Closing…':'$progress%',style:const TextStyle(fontSize:22))])),
        if(error!=null&&!leaving)Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(error!,textAlign:TextAlign.center),const SizedBox(height:16),FilledButton(autofocus:true,onPressed:()=>start(index:source),child:const Text('Retry')),
          if(sources.length>1)TextButton(onPressed:chooseSource,child:const Text('Other source'))
        ]))),
        if(c!=null&&!leaving)ValueListenableBuilder<VideoPlayerValue>(valueListenable:c,builder:(_,v,__)=>Stack(children:[
          if(v.hasError)const Center(child:CircularProgressIndicator()),
          if(v.isBuffering&&!v.hasError)const Center(child:CircularProgressIndicator()),
          if(v.caption.text.isNotEmpty)Align(alignment:controls?const Alignment(0,.45):const Alignment(0,.84),child:Container(color:const Color(0xCC000000),padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),child:Text(v.caption.text,textAlign:TextAlign.center,style:TextStyle(fontSize:widget.engine.tv?24:17)))),
          if(controls)Positioned(left:0,right:0,bottom:0,child:Container(
            decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.black])),
            padding:EdgeInsets.all(widget.engine.tv?28:12),child:Column(mainAxisSize:MainAxisSize.min,children:[
              Row(children:[Text(clock(v.position)),Expanded(child:Slider(value:v.position.inMilliseconds.clamp(0,v.duration.inMilliseconds).toDouble(),max:v.duration.inMilliseconds>0?v.duration.inMilliseconds.toDouble():1,onChanged:(n){lastAdvance=DateTime.now();c.seekTo(Duration(milliseconds:n.round()));showControls();})),Text(clock(v.duration))]),
              Wrap(alignment:WrapAlignment.center,spacing:8,children:[
                IconButton(tooltip:'Back 10 seconds',onPressed:()=>seek(-10),icon:const Icon(Icons.replay_10)),
                IconButton(focusNode:playFocus,tooltip:v.isPlaying?'Pause':'Play',onPressed:toggle,icon:Icon(v.isPlaying?Icons.pause:Icons.play_arrow)),
                IconButton(tooltip:'Forward 10 seconds',onPressed:()=>seek(10),icon:const Icon(Icons.forward_10)),
                IconButton(tooltip:'Subtitles',onPressed:captions,icon:const Icon(Icons.closed_caption)),
                IconButton(tooltip:'Audio tracks',onPressed:chooseAudio,icon:const Icon(Icons.audiotrack)),
                if(sources.length>1)IconButton(tooltip:'Playback source',onPressed:chooseSource,icon:const Icon(Icons.tune))
              ])
            ])))
        ])),
        if(controls&&!leaving)Positioned(left:12,top:8,right:12,child:Row(children:[IconButton(tooltip:'Back',onPressed:leave,icon:const Icon(Icons.arrow_back)),Expanded(child:Text(widget.movie.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:20))),if(kDebugMode)IconButton(tooltip:'Playback diagnostics',onPressed:showDiagnostics,icon:const Icon(Icons.bug_report_outlined))])),
        if(kDebugMode&&diagnostics&&!leaving)Positioned(top:64,right:16,child:IgnorePointer(child:Container(width:260,padding:const EdgeInsets.all(12),color:const Color(0xE611110F),child:c==null?diagnosticsPanel(null):ValueListenableBuilder<VideoPlayerValue>(valueListenable:c,builder:(_,v,__)=>diagnosticsPanel(v)))))
      ]))))));
  }
}
