import 'dart:async';
import 'package:flutter/foundation.dart';
import 'playback_recovery.dart';
import 'player_preferences.dart';
import 'app_preferences.dart';
import 'next_episode.dart';
import 'back_navigation.dart';
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
  bool _touchLocked=false,_mobileFullscreen=false;
  double? _doubleTapX;
  Duration? _scrubTarget;
  Future<void> _toggleFullscreen() async{
    if(widget.engine.tv||closed)return;
    final enable=!_mobileFullscreen;
    setState(()=>_mobileFullscreen=enable);
    try{
      await SystemChrome.setPreferredOrientations(enable?
        [DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]:[]);
      await SystemChrome.setEnabledSystemUIMode(enable?SystemUiMode.immersiveSticky:SystemUiMode.edgeToEdge);
    }catch(_){if(mounted&&!closed)notice('Fullscreen is unavailable on this device.');}
    if(mounted&&!closed)showControls();
  }
  Future<void> _restoreMobileDisplay() async{
    if(widget.engine.tv||!_mobileFullscreen)return;
    _mobileFullscreen=false;
    try{
      await SystemChrome.setPreferredOrientations([]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }catch(_){}
  }
  void _toggleLock(){
    if(widget.engine.tv||closed)return;
    hide?.cancel();
    setState((){_touchLocked=!_touchLocked;controls=!_touchLocked;});
    if(!_touchLocked)showControls();
  }
  void _touchTap(){
    if(_touchLocked||closed||leaving)return;
    if(controls)hideControls();
    else showControls();
  }
  late Movie _movie;
  final _nextGate=NextEpisodeGate();
  final _watchClock=Stopwatch()..start();
  final _nextFocus=FocusNode(debugLabel:'Play next episode'),_creditsFocus=FocusNode(debugLabel:'Watch credits');
  Movie? _next;
  Timer? _countdownTimer;
  int? _countdown;
  bool _nextKnown=false,_nextChecking=false,_nextDismissed=false,_nearEnd=false,
    _prepareRequested=false,_transitioning=false,_foreground=true;
  int _nextFailures=0;
  DateTime? _lastNextFailure;
  Future<void> _prepOps=Future.value();
  bool get _episodic=>_movie.isEpisode&&widget.magnet.isEmpty;
  bool get _autoplay=>AppPreferences.autoplay(widget.history.prefs);
  bool get _showNext=>_next!=null&&_nearEnd&&!_nextDismissed&&!_transitioning&&!busy&&!leaving;
  void _queuePreparation(Movie current,Movie next,int n){
    if(_prepareRequested)return;
    _prepareRequested=true;
    _prepOps=_prepOps.then((_)async{
      if(!active(n)||!_prepareRequested||_movie.id!=current.id)return;
      try{await widget.engine.prepareNext(current,next);}catch(_){}
    });
  }
  void _cancelPreparation(){
    if(!_prepareRequested)return;
    _prepareRequested=false;
    final current=_movie;
    _prepOps=_prepOps.then((_)async{try{await widget.engine.cancelNext(current);}catch(_){}});
  }
  void _stopCountdown(){
    _countdownTimer?.cancel();_countdownTimer=null;_countdown=null;
  }
  void _resetNext(){
    _stopCountdown();_nextGate.reset();
    _next=null;_nextKnown=false;_nextChecking=false;_nextDismissed=false;_nearEnd=false;
    _prepareRequested=false;_nextFailures=0;_lastNextFailure=null;
  }
  Future<void> _lookupNext(int n) async{
    if(_nextKnown||_nextChecking||_nextFailures>=2)return;
    if(_lastNextFailure!=null&&DateTime.now().difference(_lastNextFailure!)<const Duration(seconds:5))return;
    _nextChecking=true;
    final current=_movie;
    try{
      final result=await findNextEpisode(widget.engine,current);
      if(!active(n)||_movie.id!=current.id)return;
      setState((){_next=result;_nextKnown=true;});
      final c=player;
      if(c!=null&&c.value.isCompleted)_maybeCountdown();
    }catch(_){
      if(active(n)){_nextFailures++;_lastNextFailure=DateTime.now();}
    }finally{if(active(n))_nextChecking=false;}
  }
  void _sampleNext(VideoPlayerController c,int n){
    if(!_episodic||!_foreground||_transitioning)return;
    final v=c.value;
    final stable=_nextGate.sample(position:v.position,duration:v.duration,now:_watchClock.elapsed,
      playing:v.isPlaying,buffering:v.isBuffering);
    final near=v.isCompleted||NextEpisodeGate.preview(v.position,v.duration);
    if(near!=_nearEnd){
      if(!near)_stopCountdown();
      setState(()=>_nearEnd=near);
    }
    if(v.isCompleted){
      if(!_nextDismissed&&!_nextKnown)unawaited(_lookupNext(n));
      _maybeCountdown();return;
    }
    if(v.isBuffering||!v.isPlaying||v.duration<=Duration.zero||
        v.position.inMilliseconds/v.duration.inMilliseconds<.60){
      _cancelPreparation();
    }
    if(v.duration>Duration.zero&&v.position.inMilliseconds/v.duration.inMilliseconds<.60&&_nextDismissed){
      setState(()=>_nextDismissed=false);
    }
    if(_nextDismissed)return;
    if((stable&&_autoplay)||near){
      if(!_nextKnown)unawaited(_lookupNext(n));
      if(stable&&_autoplay&&_next!=null&&!v.isBuffering)_queuePreparation(_movie,_next!,n);
    }
  }
  void _maybeCountdown(){
    if(!_showNext||!_autoplay||_countdownTimer!=null||!_foreground||
        !currentRoute||settingsOpen||player?.value.isCompleted!=true)return;
    hide?.cancel();
    setState((){_countdown=5;controls=true;if(!widget.engine.tv)_touchLocked=false;});
    if(widget.engine.tv)WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&_showNext&&_countdown!=null)focusControl(_nextFocus);
    });
    _countdownTimer=Timer.periodic(const Duration(seconds:1),(_){
      if(!mounted||closed||!_foreground||!currentRoute||settingsOpen||
          !_showNext||player?.value.isCompleted!=true){
        _stopCountdown();if(mounted&&!closed)setState((){});return;
      }
      if((_countdown??0)<=1){_stopCountdown();unawaited(_playNext());}
      else{setState(()=>_countdown=_countdown!-1);}
    });
  }
  void _watchCredits(){
    _stopCountdown();_cancelPreparation();
    setState(()=>_nextDismissed=true);
    if(widget.engine.tv){showControls(focus:true);focusControl(playFocus);}
  }
  void _markSeek(Duration target,Duration duration){
    _nextGate.reset();_stopCountdown();
    if(duration>Duration.zero&&target.inMilliseconds/duration.inMilliseconds<.60){
      _nextDismissed=false;_cancelPreparation();
    }
    _nearEnd=NextEpisodeGate.preview(target,duration);
  }
  Future<void> _playNext() async{
    final next=_next;
    if(next==null||_transitioning||closed||leaving||!currentRoute||!_foreground)return;
    _transitioning=true;_stopCountdown();
    final c=player;
    final n=++generation;
    cancelAttempt();watchdog?.cancel();saveTimer?.cancel();hide?.cancel();
    setState((){player=null;busy=true;phase='Opening next episode';controls=true;progress=0;});
    if(c!=null){
      await save(c);
      try{await disposePlayback(c);}catch(_){}
    }
    if(!active(n)||leaving)return;
    // Same player route and engine: dispose the old decoder before starting
    // the next episode. Native preparation is consumed by its exact ID.
    setState((){
      _movie=next;resume=widget.history.position(next);lastPosition=resume;
      lastAdvance=DateTime.now();sources=[];captionId=null;lastControl=null;lastBottom=null;
      _resetNext();_transitioning=false;wantsPlayback=true;
    });
    await start();
  }
  bool closed=false, busy=true, controls=true, leaving=false, wantsPlayback=true;
  int generation=0, progress=0, source=0;
  String? error;
  String phase='Starting', lastFault='none';
  bool diagnostics=false;
  String? lastFailureDetail;
  final retryFocus=FocusNode(debugLabel:'Retry playback'),otherSourceFocus=FocusNode(debugLabel:'Other source');
  Map<String,dynamic> audio={}, nativeState={};
  final RecoveryBudget recovery=RecoveryBudget();
  final Stopwatch startupClock=Stopwatch();
  int? nativeReadyMs, probeMs, initializedMs, playRequestedMs, firstAdvanceMs;
  bool checkingEngineHealth=false;
  bool get nativeDirect=>kDebugMode&&AppPreferences.nativeDirect(widget.history.prefs);
  String transport='http';
  Future<void> disposePlayback(VideoPlayerController c) async {
    if(c.dataSource.startsWith('content://')){
      try{await widget.engine.cancelDirectReads(c.dataSource);}catch(_){}
    }
    await c.dispose();
  }
  String? storageFailureMessage(Object failure){
    final detail=failure.toString().toLowerCase();
    return detail.contains('not enough free device storage')||detail.contains('no space left')
      ?'Not enough free device storage. Free some space and retry playback.':null;
  }
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
  final FocusNode backFocus=FocusNode(debugLabel:'Back'), debugFocus=FocusNode(debugLabel:'Diagnostics'),
    seekFocus=FocusNode(debugLabel:'Progress bar'), rewindFocus=FocusNode(debugLabel:'Rewind'),
    forwardFocus=FocusNode(debugLabel:'Forward'), ccFocus=FocusNode(debugLabel:'Subtitles'),
    audioFocus=FocusNode(debugLabel:'Audio'), sourceFocus=FocusNode(debugLabel:'Source');
  FocusNode? lastControl, lastBottom;
  List<FocusNode> get bottomNodes=>[rewindFocus,playFocus,forwardFocus,ccFocus,audioFocus,if(sources.length>1)sourceFocus,if(_showNext)...[_nextFocus,_creditsFocus]];
  List<FocusNode> get topNodes=>[backFocus,if(kDebugMode)debugFocus];
  int get subtitleSize=>AppPreferences.size(widget.history.prefs);
  static const subtitleSizes=AppPreferences.sizes;
  double get captionFontSize=>(widget.engine.tv?24.0:17.0)*[.8,1.0,1.25,1.5][subtitleSize];
  Duration get motion=>MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:220);
  String get loadingCaption {
    if(leaving)return 'Closing playback…';
    if(phase=='Recovering playback')return 'Retrying playback…';
    if(phase=='Validating stream')return 'Checking playback…';
    if(phase=='Initializing player')return 'Starting playback…';
    if(phase=='Stopping')return 'Closing playback…';
    switch(nativeState['status']){
      case 'resolving':return _movie.isEpisode?'Finding your episode…':'Finding your movie…';
      case 'loading':return 'Establishing a connection…';
      case 'buffering':return _movie.isEpisode?'Getting your episode ready…':'Getting your movie ready…';
      default:return recovery.total>1?'Retrying playback…':_movie.isEpisode?'Finding your episode…':'Finding your movie…';
    }
  }
  void focusControl(FocusNode node){
    if(node.context!=null&&node.canRequestFocus)node.requestFocus();
  }
  bool moveControl(LogicalKeyboardKey key){
    final left=key==LogicalKeyboardKey.arrowLeft,right=key==LogicalKeyboardKey.arrowRight,
      up=key==LogicalKeyboardKey.arrowUp,down=key==LogicalKeyboardKey.arrowDown;
    if(!left&&!right&&!up&&!down)return false;
    final top=topNodes,bottom=bottomNodes;
    final t=top.indexWhere((n)=>n.hasFocus),b=bottom.indexWhere((n)=>n.hasFocus);
    // No decoder or seek bar exists on the loading/error screen.
    if(player==null||error!=null||busy){
      if(t>=0){
        if(left||right)focusControl(top[(t+(right?1:-1)).clamp(0,top.length-1).toInt()]);
        else if(down&&error!=null)focusControl(retryFocus);
      }else if(error!=null){
        if(up)focusControl(otherSourceFocus.hasFocus?retryFocus:backFocus);
        else if(down&&sources.length>1)focusControl(otherSourceFocus);
        else if(!retryFocus.hasFocus&&!otherSourceFocus.hasFocus)focusControl(retryFocus);
      }else{focusControl(backFocus);}
      return true;
    }
    if(_showNext&&(_nextFocus.hasFocus||_creditsFocus.hasFocus)){
      if(left||right)focusControl(right?_creditsFocus:_nextFocus);
      else if(up)focusControl(backFocus);
      else if(down)focusControl(playFocus);
    }else if(seekFocus.hasFocus){
      if(left||right){unawaited(seek(right?10:-10));}
      else if(up){focusControl(_showNext?_nextFocus:backFocus);}
      else{focusControl(bottom.contains(lastBottom)?lastBottom!:playFocus);}
    }else if(t>=0){
      if(left||right){focusControl(top[(t+(right?1:-1)).clamp(0,top.length-1).toInt()]);}
      else if(down&&player!=null){focusControl(seekFocus);}
    }else if(b>=0){
      if(left||right){focusControl(bottom[(b+(right?1:-1)).clamp(0,bottom.length-1).toInt()]);}
      else if(up){focusControl(seekFocus);}
    }else{
      if(player==null)return false;
      focusControl(playFocus);
    }
    return true;
  }
  String get subtitleLanguage=>AppPreferences.subtitles(widget.history.prefs);
  @override void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    unawaited(widget.engine.setPlaybackActive(true));
    _movie=widget.movie;
    resume=widget.magnet.isEmpty?widget.history.position(_movie):Duration.zero;
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
    final storage=nativeState['storage'];
    final timings=nativeState['timing'];
    String number(Object? value)=>value is num&&value>=0?value.toString():'unknown';
    String identifier(Object? value)=>value is String&&RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,47}$').hasMatch(value)?value:'unknown';
    final detail=safePlaybackDetail(e);
    final nativeStage=identifier(nativeState['failureStage']);
    final stage=nativeStage=='unknown'?identifier(nativeState['status']):nativeStage;
    final nativeType=identifier(nativeState['failureType']);
    final type=nativeType=='unknown'?identifier(e.runtimeType.toString()):nativeType;
    lastFailureDetail='$detail; stage=$stage; type=$type; selectedBytes=${number(storage is Map?storage['selectedBytes']:null)}; freeBytes=${number(storage is Map?storage['usableBytes']:null)}; reserveBytes=${number(storage is Map?storage['reserveBytes']:null)}; metadataMs=${number(timings is Map?timings['metadataMs']:null)}';
    if(kDebugMode)debugPrint('IsmePlayback: transport=$transport phase=$phase category=$lastFault attempt=${recovery.total} elapsedMs=${startupClock.elapsedMilliseconds} $lastFailureDetail');
  }
  Future<void> start({int index=0,bool resetBudget=true}) async {
    if(closed||!mounted)return;
    final old=pending;
    syncPlaybackScreen(false);
    final n=++generation;
    cancelAttempt();subtitleRevision++;audioRevision++;recommendedAudioId=null;audioTracks=[];watchdog?.cancel();saveTimer?.cancel();hide?.cancel();
    if(resetBudget){recovery.reset();lastFault='none';lastFailureDetail=null;wantsPlayback=_foreground;}
    nativeState={};_resetNext();
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
      await save(previous);await disposePlayback(previous);
    }
    var candidate=index;
    final overall=DateTime.now().add(const Duration(minutes:4));
    while(active(n)){
      recovery.record(candidate);
      startupClock..reset()..start();
      transport=nativeDirect?'direct':'http';
      if(kDebugMode)debugPrint('IsmePlayback: transport=$transport stage=start attempt=${recovery.total} sourceIndex=$candidate');
      nativeReadyMs=probeMs=initializedMs=playRequestedMs=firstAdvanceMs=null;
      setState((){source=candidate;phase=recovery.total>1?'Recovering playback':'Preparing media';progress=0;nativeState={};});
      try{
        await attempt(n,candidate,cancel,overall);
        return;
      }catch(e){
        if(!active(n))return;
        logFault(e);
        final next=DateTime.now().isBefore(overall)?nextSource(classifyPlaybackError(e)):null;
        if(next==null){
          try{await widget.engine.stop();}catch(_){}
          if(active(n))setState((){error=storageFailureMessage(e)??'Unable to play this media after ${recovery.total} attempt(s). Retry or choose another source.';busy=false;phase='Stopped';});
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
    await widget.engine.start(_movie,magnet:widget.magnet,source:index);
    while(active(n)){
      if(DateTime.now().isAfter(deadline)||DateTime.now().isAfter(overall))throw const PlaybackFailure(PlaybackFault.transient,'Media readiness deadline exceeded');
      final state=await cancellable(widget.engine.status(),cancel);
      if(!active(n))return;
      nativeState=state;
      final status=state['status'];
      if(state['sources'] is List && (state['sources'] as List).isNotEmpty) sources=(state['sources'] as List).whereType<Map<String,dynamic>>().toList();
      if(status=='error')throw StateError(state['error']?.toString()??'Could not open media');
      if(status=='ready'){
        nativeReadyMs=startupClock.elapsedMilliseconds;
        setState(()=>phase='Validating stream');
        final path=state['streamUrl'] as String?;
        if(path==null||!path.startsWith('/stream/video'))throw const PlaybackFailure(PlaybackFault.internal,'Invalid media endpoint');
        final uri=widget.engine.url(path);
        final direct=transport=='direct';
        final directUri=Uri.tryParse(state['directUri']?.toString()??'');
        if(direct&&(directUri==null||directUri.scheme!='content'||!directUri.host.endsWith('.directmedia'))){
          throw const PlaybackFailure(PlaybackFault.internal,'Native Direct unavailable');
        }
        if(!direct){
          await cancellable(widget.engine.probe(uri),cancel);
          if(!active(n))return;
          probeMs=startupClock.elapsedMilliseconds;
        }
        setState(()=>phase='Initializing player');
        if(kDebugMode)debugPrint('IsmePlayback: transport=$transport stage=initialize attempt=${recovery.total} sourceIndex=$index selectedBytes=${state['bytes']} readyMs=$nativeReadyMs probeMs=$probeMs');
        final c=direct?VideoPlayerController.contentUri(directUri!):
          VideoPlayerController.networkUrl(uri,httpHeaders:widget.engine.headers);
        bool adopted=false;
        try{
          await cancellable(c.initialize().timeout(const Duration(seconds:45)),cancel);
          if(!active(n))return;
          initializedMs=startupClock.elapsedMilliseconds;
          if(resume>Duration.zero&&resume<c.value.duration)await cancellable(c.seekTo(resume),cancel);
          if(!active(n))return;
          // Subtitle discovery and audio preference are applied after adoption; neither blocks startup.
          if(!active(n))return;
          if(wantsPlayback){
            playRequestedMs=startupClock.elapsedMilliseconds;
            await cancellable(c.play(),cancel);
          }
          if(!active(n))return;
          setState((){player=c;busy=false;phase='Playing';});
          adopted=true;
          syncPlaybackScreen(wantsPlayback);
          lastPosition=c.value.position;lastAdvance=DateTime.now();
          saveTimer=Timer.periodic(const Duration(seconds:15),(_){final current=player;if(current!=null)unawaited(save(current));});
          watchdog=Timer.periodic(const Duration(seconds:2),(_)=>monitor(c,n));
          showControls(focus:true);
          unawaited(autoSubtitles(c,n));
          unawaited(applyAudioPreference(c,n));
          return;
        }finally{if(!adopted)await disposePlayback(c);}
      }
      setState((){phase='Preparing media';progress=((state['progress'] as num?)?.round()??0).clamp(0,100).toInt();});
      // Short readiness polling only during startup; keep the byte-range probe.
      await cancellable(Future<void>.delayed(const Duration(milliseconds:250)),cancel);
    }
  }
  void monitor(VideoPlayerController c,int n){
    if(!active(n)||!identical(player,c)||busy)return;
    final v=c.value;
    if(v.hasError){
      recoverRuntime(v.errorDescription??'Playback error');return;
    }
    if(v.position!=lastPosition){
      if(firstAdvanceMs==null&&wantsPlayback&&v.isPlaying&&v.position>lastPosition){
        firstAdvanceMs=startupClock.elapsedMilliseconds;
        startupClock.stop();
        if(kDebugMode)debugPrint('IsmePlayback: transport=$transport result=playing attempt=${recovery.total} readyMs=$nativeReadyMs probeMs=$probeMs initializedMs=$initializedMs playMs=$playRequestedMs firstAdvanceMs=$firstAdvanceMs');
      }
      lastPosition=v.position;resume=v.position;lastAdvance=DateTime.now();
    }
    unawaited(checkEngineHealth(c,n));
    _sampleNext(c,n);
    if(v.isCompleted){wantsPlayback=false;syncPlaybackScreen(false);lastAdvance=DateTime.now();return;}
    if(!wantsPlayback){lastAdvance=DateTime.now();return;}
    if(DateTime.now().difference(lastAdvance)>const Duration(seconds:40)){
      recoverRuntime(const PlaybackFailure(PlaybackFault.transient,'Playback stalled'));
    }
  }
  Future<void> checkEngineHealth(VideoPlayerController c,int n) async{
    if(checkingEngineHealth)return;
    checkingEngineHealth=true;
    try{
      final state=await widget.engine.status();
      if(!active(n)||busy||!identical(player,c))return;
      nativeState=state;
      final failure=state['error']?.toString();
      if(state['status']=='error'&&failure!=null&&storageFailureMessage(failure)!=null){
        recoverRuntime(PlaybackFailure(PlaybackFault.internal,failure));
      }else if(diagnostics&&mounted){
        setState((){});
      }
    }catch(_){/* Existing player watchdog handles transport errors. */}
    finally{checkingEngineHealth=false;}
  }
  void recoverRuntime(Object failure){
    if(closed||busy)return;
    watchdog?.cancel();logFault(failure);
    final next=nextSource(classifyPlaybackError(failure));
    if(next!=null){unawaited(start(index:next,resetBudget:false));return;}
    final job=stopAfterFailure(message:storageFailureMessage(failure));
    pending=job;
    unawaited(job.whenComplete((){if(identical(pending,job))pending=null;}));
  }
  Future<void> stopAfterFailure({String? message}) async {
    if(closed||!mounted)return;
    syncPlaybackScreen(false);
    final n=++generation;cancelAttempt();saveTimer?.cancel();hide?.cancel();
    final c=player;
    setState((){player=null;busy=true;phase='Stopping';});
    if(c!=null){rememberPosition(c);await save(c);await disposePlayback(c);}
    try{await widget.engine.stop();}catch(_){}
    if(active(n))setState((){busy=false;controls=true;phase='Stopped';error=message??'Playback could not recover. Retry or choose another source.';});
  }
  Future<void> showDiagnostics() async {
    if(!kDebugMode)return;
    setState(()=>diagnostics=!diagnostics);
    if(diagnostics){
      try{final data=await widget.engine.audioDiagnostics();if(mounted&&!closed)setState(()=>audio=data);}catch(_){}
    }
  }
  Future<void> save(VideoPlayerController c) async {
    if(widget.magnet.isEmpty&&c.value.isInitialized){try{await widget.history.save(_movie,c.value.position,c.value.duration);}catch(_){}}
  }
  // Manual dismissal and idle timeout share the same animated visibility
  // state. Restore focus to the video so invisible buttons cannot be used.
  void hideControls(){
    hide?.cancel();
    if(!mounted||closed||leaving||!controls)return;
    setState(()=>controls=false);
    playerFocus.requestFocus();
  }
  void handleBack(){
    if(!currentRoute||settingsOpen)return;
    if(backHidesPlaybackControls(tv:widget.engine.tv,controlsVisible:controls,
        playbackReady:player?.value.isInitialized==true&&!busy&&error==null)){
      hideControls();
      return;
    }
    unawaited(leave());
  }
  void armControlsTimer(){
    hide?.cancel();
    if(!closed&&!settingsOpen&&!_touchLocked&&controls&&player?.value.isPlaying==true&&!_nextFocus.hasFocus&&!_creditsFocus.hasFocus){
      hide=Timer(const Duration(seconds:6),(){
        if(!mounted||closed||settingsOpen||player?.value.isPlaying!=true||_nextFocus.hasFocus||_creditsFocus.hasFocus)return;
        hideControls();
      });
    }
  }
  void showControls({bool focus=false}){
    if(!mounted||closed||leaving||(!widget.engine.tv&&_touchLocked))return;
    final reveal=!controls;
    if(reveal)setState(()=>controls=true);
    if((reveal||focus)&&player!=null&&!settingsOpen){
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted&&!closed&&controls&&!settingsOpen){final target=lastControl;focusControl(target!=null&&target.context!=null&&target.canRequestFocus?target:playFocus);}
      });
    }
    armControlsTimer();
  }
  bool get currentRoute=>mounted&&!closed&&!leaving&&ModalRoute.of(context)?.isCurrent==true;
  bool fallbackRemote(KeyEvent event){
    if(!currentRoute||settingsOpen||isBackKey(event.logicalKey))return false;
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
    if(isBackKey(key))return KeyEventResult.ignored;
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
    if(_showNext&&(_nextFocus.hasFocus||_creditsFocus.hasFocus)&&widget.engine.tv){
      if(!controls&&(key==LogicalKeyboardKey.arrowUp||key==LogicalKeyboardKey.arrowDown)){
        showControls(focus:true);return KeyEventResult.handled;
      }
      if(moveControl(key))return KeyEventResult.handled;
      return KeyEventResult.ignored;
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
    if(controls){armControlsTimer();if(widget.engine.tv&&moveControl(key))return KeyEventResult.handled;}
    return KeyEventResult.ignored;
  }
  bool _screenOn=false;
  void syncPlaybackScreen(bool active){
    final next=active&&_foreground&&!closed&&AppPreferences.awake(widget.history.prefs);
    if(next==_screenOn)return;
    _screenOn=next;
    unawaited(widget.engine.setPlaybackScreenOn(next));
  }
  Future<void> setPlaying(bool value) async{
    final c=player;if(c==null||closed||busy)return;
    wantsPlayback=value;lastAdvance=DateTime.now();
    syncPlaybackScreen(value);
    if(!value){_stopCountdown();_nextGate.reset();_cancelPreparation();if(c.value.isCompleted)setState(()=>_nextDismissed=true);}
    try{
      if(value){if(c.value.isCompleted){_markSeek(Duration.zero,c.value.duration);await c.seekTo(Duration.zero);}await c.play();}
      else{await c.pause();}
    }catch(e){if(identical(c,player)&&!closed)recoverRuntime(e);}
    if(identical(c,player))showControls();
  }
  Future<void> toggle() => setPlaying(!wantsPlayback);
  Future<void> seek(int seconds) async {
    final c=player;if(c==null||closed||busy)return;
    final target=(c.value.position.inMilliseconds+seconds*1000).clamp(0,c.value.duration.inMilliseconds).toInt();
    lastAdvance=DateTime.now();
    setState(()=>_markSeek(Duration(milliseconds:target),c.value.duration));
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
    try{
      if(!widget.engine.tv)return await showModalBottomSheet<T>(context:context,isScrollControlled:true,showDragHandle:true,
        builder:(ctx)=>SafeArea(child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(ctx).height*.82),
          child:SingleChildScrollView(child:builder(ctx)))));
      return await showDialog<T>(context:context,builder:(ctx)=>Shortcuts(shortcuts:const {SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),SingleActivator(LogicalKeyboardKey.enter):ActivateIntent()},child:builder(ctx)));}
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
          TextButton(autofocus:true,onPressed:()=>Navigator.pop(ctx,{'id':-2}),child:Text('Subtitle size: ${subtitleSizes[subtitleSize]}')),
          TextButton(onPressed:()=>Navigator.pop(ctx,{'id':-1,'lang':'off'}),child:Text(captionId==null?'Off (no active track)':'Off')),
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
      final id=choice['id'] as int;
      if(id==-2){await chooseSubtitleSize();return;}
      final revision=++subtitleRevision;
      if(id<0){
        await c.setClosedCaptionFile(null);
        if(samePlayer(c,n)&&revision==subtitleRevision){
          setState(()=>captionId=null);
          await widget.history.prefs.setString(AppPreferences.subtitleLanguageKey,'off');
        }
      }else{
        final raw=await widget.engine.caption(id);
        if(!samePlayer(c,n)||revision!=subtitleRevision)return;
        await c.setClosedCaptionFile(Future.value(WebVTTCaptionFile(raw)));
        if(samePlayer(c,n)&&revision==subtitleRevision){
          setState(()=>captionId=id);
          await widget.history.prefs.setString(AppPreferences.subtitleLanguageKey,AppPreferences.language(choice['lang']?.toString()));
        }
      }
    }catch(_){if(samePlayer(c,n))notice('Subtitles unavailable.');}
    finally{if(samePlayer(c,n))showControls();}
  }
  Future<void> chooseSubtitleSize() async {
    final value=await settingsDialog<int>((ctx)=>SimpleDialog(title:const Text('Subtitle size'),children:[
      for(var i=0;i<subtitleSizes.length;i++)
        TextButton(autofocus:i==subtitleSize,onPressed:()=>Navigator.pop(ctx,i),
          child:Text(subtitleSizes[i]+(i==subtitleSize?' (selected)':''),style:TextStyle(fontSize:16.0+i*3))),
    ]));
    if(value==null||!mounted||closed)return;
    await widget.history.prefs.setInt(AppPreferences.subtitleSizeKey,value);
    if(mounted&&!closed)setState((){});
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
    _foreground=state==AppLifecycleState.resumed;
    if(!_foreground){syncPlaybackScreen(false);_stopCountdown();_nextGate.reset();_cancelPreparation();wantsPlayback=false;final c=player;if(c!=null){unawaited(c.pause());unawaited(save(c));}}
    if(mounted&&!closed)setState((){});
  }
  Future<void> shutdown() async {
    if(closed)return;syncPlaybackScreen(false);closed=true;generation++;subtitleRevision++;cancelAttempt();hide?.cancel();saveTimer?.cancel();watchdog?.cancel();_stopCountdown();_cancelPreparation();
    final c=player;player=null;
    if(c!=null){await save(c);try{await disposePlayback(c);}catch(_){}}
    // Cancel engine while a pending initialization/poll is in flight.
    try{await widget.engine.stop();}catch(_){}
    final job=pending;if(job!=null){try{await job;}catch(_){}}
    try{await widget.engine.stop();}catch(_){}
  }
  Future<void> leave() async {
    if(leaving||!currentRoute)return;
    setState(()=>leaving=true);
    try{await shutdown();}
    finally{
      await _restoreMobileDisplay();
      if(mounted)popCurrentPage(context);
    }
  }
  @override void dispose(){unawaited(widget.engine.setPlaybackActive(false));HardwareKeyboard.instance.removeHandler(fallbackRemote);WidgetsBinding.instance.removeObserver(this);unawaited(shutdown());unawaited(_restoreMobileDisplay());playerFocus.dispose();for(final node in [retryFocus,otherSourceFocus,playFocus,backFocus,debugFocus,seekFocus,rewindFocus,forwardFocus,ccFocus,audioFocus,sourceFocus,_nextFocus,_creditsFocus]){node.dispose();}super.dispose();}
  String clock(Duration d){final h=d.inHours,m=d.inMinutes.remainder(60).toString().padLeft(2,'0'),s=d.inSeconds.remainder(60).toString().padLeft(2,'0');return h>0?'$h:$m:$s':'$m:$s';}
  Widget diagnosticsPanel(VideoPlayerValue? v){
    final position=v?.position??resume;
    final buffered=v?.buffered.where((r)=>r.start<=position&&r.end>=position).fold<int>(0,(max,r){
      final ms=(r.end-position).inMilliseconds;return ms>max?ms:max;
    })??0;
    final timings=nativeState['timing'];
    final storage=nativeState['storage'];
    String ms(Object? value)=>value is num&&value>=0?'${value} ms':'—';
    String mib(Object? value)=>value is num&&value>=0?'${(value/1048576).round()} MiB':'—';
    final rows=<String,String>{
      'Resolve / metadata': '${ms(timings is Map?timings['resolvedMs']:null)} / ${ms(timings is Map?timings['metadataMs']:null)}',
      'Ready / probe / init': '${ms(nativeReadyMs)} / ${ms(probeMs)} / ${ms(initializedMs)}',
      'Play / first advance': '${ms(playRequestedMs)} / ${ms(firstAdvanceMs)}',
      'Free / reserved': '${mib(storage is Map?storage['usableBytes']:null)} / ${mib(storage is Map?storage['reserveBytes']:null)}',
      'Transport':transport,
      'Phase':phase,'Attempts':'${recovery.total}/${RecoveryBudget.maxAttempts}',
      'Last error':lastFault,'Engine':nativeState['status']?.toString()??'—',
      if(lastFailureDetail!=null)'Failure detail':lastFailureDetail!,
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
  Widget controlButton(FocusNode node,String label,IconData icon,VoidCallback action,{bool compact=false}){
    return Focus(canRequestFocus:false,onFocusChange:(value){
      if(value){lastControl=node;if(bottomNodes.contains(node))lastBottom=node;armControlsTimer();}
    },child:IconButton(focusNode:node,tooltip:label,onPressed:action,icon:Icon(icon),
      iconSize:widget.engine.tv?28:23,
      style:ButtonStyle(
        minimumSize:WidgetStatePropertyAll(Size(widget.engine.tv&&!compact?54:44,widget.engine.tv&&!compact?54:44)),
        backgroundColor:WidgetStateProperty.resolveWith((states)=>states.contains(WidgetState.focused)?const Color(0x55FFFFFF):Colors.transparent),
        foregroundColor:WidgetStateProperty.resolveWith((states)=>states.contains(WidgetState.focused)?CinemaColors.accent:CinemaColors.ink),
      )));
  }
  Widget controlOverlay(Widget child,{required bool top}){
    final visible=controls&&!leaving;
    return ExcludeFocus(excluding:!visible,child:IgnorePointer(ignoring:!visible,
      child:AnimatedSlide(duration:motion,curve:Curves.easeOutCubic,
        offset:visible?Offset.zero:Offset(0,top?-.12:.12),
        child:AnimatedOpacity(duration:motion,curve:Curves.easeOutCubic,opacity:visible?1:0,child:child))));
  }
  Widget loadingView({required String caption,String? percentage}){
    return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const CircularProgressIndicator(),const SizedBox(height:18),
      if(percentage!=null)Text(percentage,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w600)),
      const SizedBox(height:8),
      AnimatedSwitcher(duration:motion,child:Text(caption,key:ValueKey(caption),
        textAlign:TextAlign.center,style:const TextStyle(fontSize:14,color:CinemaColors.muted))),
    ]));
  }
  Widget nextEpisodeOverlay(){
    final next=_next!;
    final tv=widget.engine.tv;
    final remaining=_countdown;
    final screen=MediaQuery.sizeOf(context);
    final width=(screen.width*(tv ? .42 : (screen.width<screen.height ? .78 : .38))).clamp(150.0,tv?300.0:280.0).toDouble();
    final identity=EpisodeIdentity.parse(next);
    return Positioned(right:tv?32:12,bottom:controls?(tv?124:132):24,
      child:ConstrainedBox(constraints:BoxConstraints(maxWidth:width),
        child:Material(color:const Color(0xF0222220),borderRadius:BorderRadius.circular(12),clipBehavior:Clip.antiAlias,
          child:Padding(padding:const EdgeInsets.all(10),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            if(MediaQuery.sizeOf(context).height>420)AspectRatio(aspectRatio:16/9,child:ClipRRect(borderRadius:BorderRadius.circular(8),
              child:CinemaArt(next.art,cacheWidth:480))),
            const SizedBox(height:6),
            Text('UP NEXT${identity==null?'':' · S${identity.season} E${identity.episode}'}',
              style:const TextStyle(color:CinemaColors.accent,fontSize:10,fontWeight:FontWeight.w700,letterSpacing:1)),
            const SizedBox(height:3),
            Text(next.episodeTitle.isEmpty?next.title:next.episodeTitle,maxLines:2,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontSize:tv?17:14,fontWeight:FontWeight.w600)),
            const SizedBox(height:7),
            if(remaining!=null)LinearProgressIndicator(value:(5-remaining)/5,backgroundColor:const Color(0xFF444444)),
            const SizedBox(height:7),
            FilledButton(focusNode:_nextFocus,onPressed:_playNext,child:Text(remaining==null?'Play next':'Next episode in ${remaining}s')),
            TextButton(focusNode:_creditsFocus,onPressed:_watchCredits,child:const Text('Watch credits')),
          ])))));
  }
  Widget progressBar(VideoPlayerController c,VideoPlayerValue v){
    final tv=widget.engine.tv;
    final max=v.duration.inMilliseconds>0?v.duration.inMilliseconds.toDouble():1.0;
    if(!tv)return Slider(value:(_scrubTarget??v.position).inMilliseconds.clamp(0,max).toDouble(),max:max,
      onChangeStart:(n){hide?.cancel();setState(()=>_scrubTarget=Duration(milliseconds:n.round()));},
      onChanged:(n){setState(()=>_scrubTarget=Duration(milliseconds:n.round()));},
      onChangeEnd:(n){
        final target=Duration(milliseconds:n.round());
        setState((){_scrubTarget=null;_markSeek(target,c.value.duration);});
        unawaited(c.seekTo(target));showControls();
      });
    final slider=Slider(value:v.position.inMilliseconds.clamp(0,max).toDouble(),max:max,
      onChanged:(n){lastAdvance=DateTime.now();final target=Duration(milliseconds:n.round());_markSeek(target,c.value.duration);unawaited(c.seekTo(target));showControls();if(mounted)setState((){});});
    // A TV's slider must not consume up/down as value-changing keys.
    // Own its focus explicitly and keep the underlying touch slider usable.
    return Focus(focusNode:seekFocus,onFocusChange:(focused){
      if(focused){lastControl=seekFocus;armControlsTimer();}
      if(mounted)setState((){});
    },onKeyEvent:(_,event){
      if(event is KeyDownEvent||event is KeyRepeatEvent){
        final key=event.logicalKey;
        if(key==LogicalKeyboardKey.select||key==LogicalKeyboardKey.enter)return KeyEventResult.handled;
        return handleRemote(event);
      }
      return KeyEventResult.ignored;
    },child:AnimatedContainer(duration:motion,
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),
        color:seekFocus.hasFocus?const Color(0x22FFFFFF):Colors.transparent),
      child:ExcludeFocus(child:slider)));
  }
  Widget _touchButton(String label,IconData icon,VoidCallback action,{double size=24})=>IconButton(
    tooltip:label,onPressed:action,icon:Icon(icon,size:size),style:IconButton.styleFrom(
      foregroundColor:CinemaColors.ink,minimumSize:const Size(48,48),tapTargetSize:MaterialTapTargetSize.padded));
  Widget _touchCenter(VideoPlayerValue v)=>controlOverlay(Row(mainAxisAlignment:MainAxisAlignment.center,children:[
    _touchButton('Back 10 seconds',Icons.replay_10,()=>seek(-10),size:30),
    const SizedBox(width:12),
    IconButton.filled(onPressed:toggle,tooltip:v.isPlaying?'Pause':'Play',icon:Icon(v.isPlaying?Icons.pause:Icons.play_arrow,size:38),
      style:IconButton.styleFrom(backgroundColor:const Color(0x55FFFFFF),foregroundColor:CinemaColors.ink,minimumSize:const Size(68,68))),
    const SizedBox(width:12),
    _touchButton('Forward 10 seconds',Icons.forward_10,()=>seek(10),size:30),
  ]),top:false);
  Widget _touchBottom(VideoPlayerController c,VideoPlayerValue v)=>controlOverlay(Container(
    decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,
      colors:[Colors.transparent,Color(0xDD000000),CinemaColors.black])),
    padding:const EdgeInsets.fromLTRB(12,12,12,6),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(children:[
        Text(clock(_scrubTarget??v.position),style:const TextStyle(fontSize:12)),
        Expanded(child:progressBar(c,v)),Text(clock(v.duration),style:const TextStyle(fontSize:12)),
      ]),
      Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
        _touchButton('Subtitles',Icons.closed_caption_outlined,captions),
        _touchButton('Audio tracks',Icons.audiotrack,chooseAudio),
        if(sources.length>1)_touchButton('Playback source',Icons.tune,chooseSource),
        _touchButton(_mobileFullscreen?'Exit fullscreen':'Fullscreen',_mobileFullscreen?Icons.fullscreen_exit:Icons.fullscreen,()=>unawaited(_toggleFullscreen())),
      ]),
    ])),top:false);
  Widget playbackControls(VideoPlayerController c,VideoPlayerValue v){
    final tv=widget.engine.tv;
    if(!tv)return _touchBottom(c,v);
    return controlOverlay(Container(
      decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,
        colors:[Colors.transparent,Color(0xCC000000),CinemaColors.black],stops:[0,.55,1])),
      padding:EdgeInsets.fromLTRB(tv?32:12,24,tv?32:12,tv?16:8),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        Row(children:[
          Text(clock(v.position),style:const TextStyle(fontSize:13)),
          Expanded(child:progressBar(c,v)),
          Text(clock(v.duration),style:const TextStyle(fontSize:13)),
        ]),
        Wrap(alignment:WrapAlignment.center,spacing:tv?12:4,children:[
          controlButton(rewindFocus,'Back 10 seconds',Icons.replay_10,()=>seek(-10)),
          controlButton(playFocus,v.isPlaying?'Pause':'Play',v.isPlaying?Icons.pause:Icons.play_arrow,toggle),
          controlButton(forwardFocus,'Forward 10 seconds',Icons.forward_10,()=>seek(10)),
          controlButton(ccFocus,'Subtitles',Icons.closed_caption,captions),
          controlButton(audioFocus,'Audio tracks',Icons.audiotrack,chooseAudio),
          if(sources.length>1)controlButton(sourceFocus,'Playback source',Icons.tune,chooseSource),
        ]),
      ])),top:false);
  }
  @override Widget build(BuildContext context){
    final c=player;
    return BackNavigationScope(onBack:handleBack,
      child:Scaffold(backgroundColor:CinemaColors.black,body:SafeArea(child:Focus(
      focusNode:playerFocus,autofocus:true,onKeyEvent:(_,event)=>handleRemote(event),
      child:Shortcuts(shortcuts:const {SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),SingleActivator(LogicalKeyboardKey.enter):ActivateIntent()},child:Stack(fit:StackFit.expand,children:[
        if(c!=null&&!leaving)GestureDetector(behavior:widget.engine.tv?HitTestBehavior.deferToChild:HitTestBehavior.opaque,
          onTap:widget.engine.tv?showControls:_touchTap,
          onDoubleTapDown:widget.engine.tv||_touchLocked?null:(details)=>_doubleTapX=details.localPosition.dx,
          onDoubleTap:widget.engine.tv||_touchLocked?null:(){
            final x=_doubleTapX;if(x==null)return;
            unawaited(seek(x<MediaQuery.sizeOf(context).width/2?-10:10));
          },
          child:Center(child:AspectRatio(aspectRatio:c.value.aspectRatio,child:VideoPlayer(c)))),
        if(busy||leaving)loadingView(caption:loadingCaption,percentage:leaving?null:'$progress%'),
        if(error!=null&&!leaving)Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(error!,textAlign:TextAlign.center),const SizedBox(height:16),FilledButton(focusNode:retryFocus,autofocus:true,onPressed:()=>start(index:source),child:const Text('Retry')),
          if(sources.length>1)TextButton(focusNode:otherSourceFocus,onPressed:chooseSource,child:const Text('Other source'))
        ]))),
        if(c!=null&&!leaving)ValueListenableBuilder<VideoPlayerValue>(valueListenable:c,builder:(_,v,__)=>Stack(children:[
          if(v.hasError)loadingView(caption:'Checking playback…'),
          if(v.isBuffering&&!v.hasError)loadingView(caption:'Buffering playback…'),
          if(v.caption.text.isNotEmpty)AnimatedAlign(duration:motion,curve:Curves.easeOutCubic,
            alignment:controls?const Alignment(0,.34):const Alignment(0,.84),
            child:ConstrainedBox(constraints:BoxConstraints(maxWidth:MediaQuery.sizeOf(context).width*.88),
              child:Container(color:const Color(0xCC000000),padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
                child:Text(v.caption.text,textAlign:TextAlign.center,style:TextStyle(fontSize:captionFontSize,height:1.25))))),
          if(!widget.engine.tv&&!_touchLocked&&!_showNext)Center(child:_touchCenter(v)),
          if(widget.engine.tv||!_touchLocked)Positioned(left:0,right:0,bottom:0,child:playbackControls(c,v)),
        ])),
        if(!leaving&&(widget.engine.tv||!_touchLocked))Positioned(left:0,top:0,right:0,child:controlOverlay(Container(
          decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,
            colors:[Color(0xDD000000),Colors.transparent])),
          padding:EdgeInsets.fromLTRB(widget.engine.tv?24:8,8,widget.engine.tv?24:8,22),
          child:Row(children:[
            controlButton(backFocus,'Back',Icons.arrow_back,(){
              unawaited(leave());
            },compact:true),
            Expanded(child:Text(_movie.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w600))),
            if(!widget.engine.tv&&c!=null)_touchButton('Lock controls',Icons.lock_open,_toggleLock),
            if(kDebugMode&&widget.engine.tv)controlButton(debugFocus,'Playback diagnostics',Icons.bug_report_outlined,showDiagnostics,compact:true),
          ])),top:true)),
        if(_touchLocked&&!widget.engine.tv&&!leaving)Positioned(top:8,right:8,child:IconButton.filledTonal(
          tooltip:'Unlock controls',onPressed:_toggleLock,icon:const Icon(Icons.lock))),
        if(_showNext&&c!=null&&(widget.engine.tv||!_touchLocked))nextEpisodeOverlay(),
        if(kDebugMode&&diagnostics&&!leaving)Positioned(top:64,right:16,bottom:16,child:IgnorePointer(child:Align(alignment:Alignment.topRight,child:Container(width:300,padding:const EdgeInsets.all(12),color:const Color(0xE611110F),child:SingleChildScrollView(child:c==null?diagnosticsPanel(null):ValueListenableBuilder<VideoPlayerValue>(valueListenable:c,builder:(_,v,__)=>diagnosticsPanel(v)))))))
      ]))))));
  }
}
