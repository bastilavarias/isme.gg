import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared monotonic gate prevents a single physical Back action (or key
/// repeat during a route transition) from stepping through multiple screens.
class BackPressGate {
  final Duration Function() now;
  final Duration cooldown;
  Duration? _blockedUntil;
  BackPressGate({required this.now,this.cooldown=const Duration(milliseconds:350)});
  bool accept(){
    final time=now();
    if(_blockedUntil!=null&&time<_blockedUntil!)return false;
    _blockedUntil=time+cooldown;
    return true;
  }
  void block(){_blockedUntil=now()+cooldown;}
}
final _backClock=Stopwatch()..start();
final appBackGate=BackPressGate(now:()=>_backClock.elapsed);

bool isBackKey(LogicalKeyboardKey key)=>key==LogicalKeyboardKey.escape||
  key==LogicalKeyboardKey.goBack||key==LogicalKeyboardKey.browserBack;

/// Pop only the route that initiated this action. Explicit pop bypasses the
/// PopScope after cleanup; maybePop is used for all user Back controls.
void popCurrentPage(BuildContext context,{BackPressGate? gate}){
  if(!context.mounted||ModalRoute.of(context)?.isCurrent!=true)return;
  final navigator=Navigator.of(context);
  if(!navigator.canPop())return;
  (gate??appBackGate).block();
  navigator.pop();
}

class BackNavigationScope extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final BackPressGate? gate;
  const BackNavigationScope({super.key,required this.child,this.onBack,this.gate});
  void _request(BuildContext context){
    if(ModalRoute.of(context)?.isCurrent!=true)return;
    final guard=gate??appBackGate;
    if(!guard.accept())return;
    if(onBack!=null){onBack!();}
    else{popCurrentPage(context,gate:guard);}
  }
  @override Widget build(BuildContext context)=>PopScope<Object?>(
    canPop:false,
    onPopInvokedWithResult:(didPop,_) {if(!didPop)_request(context);},
    child:Focus(canRequestFocus:false,onKeyEvent:(_,event){
      if(!isBackKey(event.logicalKey)||ModalRoute.of(context)?.isCurrent!=true)return KeyEventResult.ignored;
      if(event is KeyDownEvent)_request(context);
      // Consume repeat and key-up as well; a held remote key is one action.
      return KeyEventResult.handled;
    },child:child));
}

/// TV remote Back dismisses visible controls first. Mobile Back always
/// leaves the player; touch controls have their own tap-to-hide gesture.
bool backHidesPlaybackControls({required bool tv,required bool controlsVisible,required bool playbackReady})=>
  tv&&controlsVisible&&playbackReady;

class ExitPressCounter {
  final Duration window;
  int count=0;
  Duration? _first;
  ExitPressCounter({this.window=const Duration(seconds:3)});
  int press(Duration now){
    if(_first==null||now-_first!>=window){count=0;_first=now;}
    return ++count;
  }
  void reset(){count=0;_first=null;}
}

/// Only the actual home screen can exit the app. Category/search/filter
/// navigation is unwound first and never counts as an exit press.
class HomeBackGuard extends StatefulWidget {
  final Widget child;
  final Object locationKey;
  final bool Function() navigateHome;
  final BackPressGate? gate;
  final Future<void> Function()? exitApp;
  const HomeBackGuard({super.key,required this.child,required this.locationKey,
    required this.navigateHome,this.gate,this.exitApp});
  @override State<HomeBackGuard> createState()=>_HomeBackGuardState();
}
class _HomeBackGuardState extends State<HomeBackGuard> with WidgetsBindingObserver {
  final _counter=ExitPressCounter();
  bool _exiting=false;
  BackPressGate get _gate=>widget.gate??appBackGate;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(ModalRoute.isCurrentOf(context)!=true)_counter.reset();
  }
  @override void didUpdateWidget(covariant HomeBackGuard oldWidget){
    super.didUpdateWidget(oldWidget);
    if(oldWidget.locationKey!=widget.locationKey)_counter.reset();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    _counter.reset();
    if(state==AppLifecycleState.resumed)_exiting=false;
  }
  void _back(){
    if(_exiting)return;
    if(widget.navigateHome()){
      _counter.reset();
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      return;
    }
    final presses=_counter.press(_gate.now());
    final messenger=ScaffoldMessenger.maybeOf(context);
    messenger?.removeCurrentSnackBar();
    if(presses>=3){
      _counter.reset();_exiting=true;
      unawaited(_exit());
      return;
    }
    messenger?.showSnackBar(SnackBar(
      content:Text(presses==1?'Press Back 2 more times to exit':'Press Back once more to exit'),
      duration:const Duration(seconds:2),behavior:SnackBarBehavior.floating));
  }
  Future<void> _exit() async {
    try{await (widget.exitApp?.call()??SystemNavigator.pop());}
    catch(_){if(mounted)_exiting=false;}
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override Widget build(BuildContext context)=>BackNavigationScope(
    gate:_gate,onBack:_back,child:Listener(
      onPointerDown:(_)=>_counter.reset(),child:widget.child));
}

/// Continue Watching can still resume in one action, with the title page
/// underneath the player so Back returns to the episode list.
Future<void> pushTitleRoute(BuildContext context,Widget details,{Widget? resumePlayer}) async {
  if(!context.mounted||ModalRoute.of(context)?.isCurrent!=true)return;
  final navigator=Navigator.of(context);
  final detailsClosed=navigator.push<void>(MaterialPageRoute(builder:(_)=>details));
  if(resumePlayer!=null){
    await navigator.push<void>(MaterialPageRoute(builder:(_)=>resumePlayer));
  }
  await detailsClosed;
}
