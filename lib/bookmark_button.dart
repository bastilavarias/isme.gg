import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'engine.dart';

class BookmarkButton extends StatefulWidget {
  final Movie movie;
  final BookmarkStore store;
  final FocusNode? focusNode;
  const BookmarkButton({super.key,required this.movie,required this.store,this.focusNode});
  @override State<BookmarkButton> createState()=>_BookmarkButtonState();
}
class _BookmarkButtonState extends State<BookmarkButton>{
  bool busy=false;
  Future<void> toggle() async{
    if(busy)return;
    setState(()=>busy=true);
    try{await widget.store.toggle(widget.movie);}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not update My List. Try again.')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.store,builder:(_,__){
    final saved=widget.store.contains(widget.movie);
    return Shortcuts(shortcuts:const {SingleActivator(LogicalKeyboardKey.select):ActivateIntent()},
      child:Semantics(toggled:saved,child:OutlinedButton.icon(
      key:const ValueKey('bookmark-toggle'),focusNode:widget.focusNode,
      // Keep focus when a write is in flight; toggle guards repeated activation.
      onPressed:BookmarkStore.valid(BookmarkStore.parent(widget.movie))?toggle:null,
      icon:Icon(saved?Icons.bookmark:Icons.bookmark_border,color:saved?CinemaColors.accent:null),
      label:Text(saved?'Saved':'My List'),style:OutlinedButton.styleFrom(minimumSize:const Size(0,48)))));
  });
}
