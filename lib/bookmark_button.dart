import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'engine.dart';

class BookmarkButton extends StatefulWidget {
  final Movie movie;
  final BookmarkStore store;
  final FocusNode? focusNode;
  final bool tv;
  const BookmarkButton({super.key,required this.movie,required this.store,this.focusNode,this.tv=false});
  @override State<BookmarkButton> createState()=>_BookmarkButtonState();
}
class _BookmarkButtonState extends State<BookmarkButton>{
  bool busy=false;
  final _remoteClock=Stopwatch()..start();
  Duration? _lastRemoteActivation;
  bool get _enabled=>BookmarkStore.valid(BookmarkStore.parent(widget.movie));
  KeyEventResult _remoteKeys(FocusNode node,KeyEvent event){
    final key=event.logicalKey;
    if(key!=LogicalKeyboardKey.select&&key!=LogicalKeyboardKey.enter&&key!=LogicalKeyboardKey.numpadEnter&&key!=LogicalKeyboardKey.gameButtonA)return KeyEventResult.ignored;
    // Consume the complete activation sequence. The default button shortcut
    // can repeat while a remote is held, undoing the just-saved bookmark.
    if(event is KeyDownEvent&&_enabled){
      final now=_remoteClock.elapsed;
      if(_lastRemoteActivation==null||now-_lastRemoteActivation!>=const Duration(milliseconds:350)){
        _lastRemoteActivation=now;
        toggle();
      }
    }
    return KeyEventResult.handled;
  }
  Future<void> toggle() async{
    if(busy)return;
    setState(()=>busy=true);
    try{
      await widget.store.toggle(widget.movie);
      if(mounted){
        final saved=widget.store.contains(widget.movie);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(saved?'Added to My List':'Removed from My List'),duration:const Duration(seconds:2)));
      }
    }
    catch(e){debugPrint('Bookmark update failed: $e');if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not update My List. Try again.')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.store,builder:(_,__){
    final saved=widget.store.contains(widget.movie);
    final button=Semantics(toggled:saved,child:TextButton.icon(
      key:const ValueKey('bookmark-toggle'),focusNode:widget.focusNode,
      // Keep focus when a write is in flight; toggle guards repeated activation.
      onPressed:_enabled?toggle:null,
      icon:Icon(saved?Icons.bookmark:Icons.bookmark_border,color:saved?CinemaColors.accent:null),
      label:Text(saved?'Saved':'My List'),style:TextButton.styleFrom(
        foregroundColor:CinemaColors.accent,minimumSize:const Size(0,48),
        backgroundColor:Colors.transparent)));
    return widget.tv?Focus(canRequestFocus:false,onKeyEvent:_remoteKeys,child:button):
      Shortcuts(shortcuts:const {SingleActivator(LogicalKeyboardKey.select):ActivateIntent()},child:button);
  });
}
