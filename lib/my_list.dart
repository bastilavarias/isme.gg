import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'back_navigation.dart';
import 'design.dart';
import 'engine.dart';
import 'mobile/mobile_widgets.dart';

class MyList extends StatefulWidget {
  final BookmarkStore store;
  final NativeEngine engine;
  final Future<void> Function(BuildContext,Movie) onOpen;
  final bool tv;
  const MyList({super.key,required this.store,required this.engine,required this.onOpen,this.tv=false});
  @override State<MyList> createState()=>_MyListState();
}
class _MyListState extends State<MyList>{
  String filter='All';
  bool alphabetical=false,opening=false;
  final nodes=<String,FocusNode>{};
  final back=FocusNode(debugLabel:'My List back');
  final scroll=ScrollController();
  FocusNode node(Movie movie)=>nodes.putIfAbsent(movie.id,()=>FocusNode(debugLabel:movie.title));
  @override void dispose(){for(final n in nodes.values){n.dispose();}back.dispose();scroll.dispose();super.dispose();}
  List<Movie> filtered(List<Movie> movies){
    final items=movies.where((m)=>switch(filter){
      'Movies'=>!m.episodic&&!m.animeFilm,
      'Series'=>m.type=='Series',
      'Anime'=>m.type=='Anime'||m.animeFilm,
      _=>true,
    }).toList();
    if(alphabetical)items.sort((a,b)=>a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return items;
  }
  Future<void> open(Movie movie) async{
    if(opening)return;
    opening=true;
    try{await widget.onOpen(context,movie);}
    finally{
      opening=false;
      if(mounted&&widget.tv){
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(!mounted||ModalRoute.of(context)?.isCurrent!=true)return;
          final target=nodes[movie.id];
          if(widget.store.contains(movie)&&target?.context!=null){target!.requestFocus();}
          else{back.requestFocus();}
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
  }
  Future<void> remove(Movie movie) async{
    try{await widget.store.remove(movie);}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not remove title. Try again.')));}
  }
  Future<void> menu(Movie movie) async{
    final result=await showModalBottomSheet<bool>(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(child:ListTile(
      leading:const Icon(Icons.bookmark_remove_outlined),title:const Text('Remove from My List'),
      subtitle:Text(movie.title),onTap:()=>Navigator.pop(ctx,true))));
    if(mounted&&result==true)await remove(movie);
  }
  Widget filters()=>SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:16),
    child:Row(children:[for(final label in ['All','Movies','Series','Anime'])Padding(
      padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(label),selected:filter==label,
        onSelected:(_){if(scroll.hasClients)scroll.jumpTo(0);setState(()=>filter=label);}))]));
  Widget poster(Movie m)=>widget.tv?RemoteTile(key:ValueKey('saved-${m.id}'),focusNode:node(m),label:m.title,
    onPressed:()=>open(m),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Expanded(child:CinemaArt(m.poster.isEmpty?m.art:m.poster)),
      Padding(padding:const EdgeInsets.all(6),child:Text(m.title,maxLines:1,overflow:TextOverflow.ellipsis)),
    ])):GestureDetector(key:ValueKey('saved-${m.id}'),onLongPress:()=>menu(m),
      child:MobilePoster(movie:m,engine:widget.engine,onOpen:()=>open(m)));
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.store,builder:(context,_){
    final all=widget.store.movies,items=filtered(all),tv=widget.tv;
    final body=Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:EdgeInsets.fromLTRB(tv?40:16,10,tv?40:16,8),child:Row(children:[
        if(tv)IconButton(focusNode:back,autofocus:true,tooltip:'Back',onPressed:()=>Navigator.maybePop(context),icon:const Icon(Icons.arrow_back)),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('My List',style:TextStyle(fontSize:tv?32:26,fontWeight:FontWeight.w800)),
          Text('${all.length} saved ${all.length==1?'title':'titles'}',style:const TextStyle(color:CinemaColors.muted)),
        ])),
        IconButton(tooltip:alphabetical?'Sort by recently added':'Sort alphabetically',
          onPressed:(){if(scroll.hasClients)scroll.jumpTo(0);setState(()=>alphabetical=!alphabetical);},icon:const Icon(Icons.sort)),
      ])),
      if(all.isNotEmpty)filters(),
      Expanded(child:items.isEmpty?MobileEmpty(all.isEmpty?'Your list is empty':'No saved titles in this category',
        all.isEmpty?'Save movies and shows from their details page.':'Choose another filter.'):
        LayoutBuilder(builder:(context,box){
          final count=((box.maxWidth-(tv?80:32))/(tv?150:113)).floor().clamp(2,8).toInt();
          return GridView.builder(controller:scroll,padding:EdgeInsets.fromLTRB(tv?40:16,10,tv?40:16,24),
            gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:count,childAspectRatio:.60,crossAxisSpacing:12,mainAxisSpacing:12),
            itemCount:items.length,itemBuilder:(_,i)=>poster(items[i]));
        })),
    ]);
    return tv?BackNavigationScope(child:Scaffold(body:SafeArea(child:Shortcuts(shortcuts:const {
      SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter):ActivateIntent(),
    },child:body)))):body;
  });
}
