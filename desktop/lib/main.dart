import 'dart:async';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ismegg/design.dart';
import 'package:ismegg/engine.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog.dart';
import 'local_player.dart';
import 'cinema_scene.dart';
import 'title_page.dart';
import 'native_engine.dart';
import 'stream_player.dart';

Future<void> main()async{
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs=await SharedPreferences.getInstance();
  runApp(DesktopApp(prefs:prefs,catalog:CinemetaDesktopCatalog()));
}

class DesktopApp extends StatelessWidget{
  final SharedPreferences prefs;
  final DesktopCatalog catalog;
  const DesktopApp({super.key,required this.prefs,required this.catalog});
  @override Widget build(BuildContext context){
    final theme=cinemaTheme();
    return MaterialApp(title:'isme.gg Desktop',debugShowCheckedModeBanner:false,
      theme:theme.copyWith(
        colorScheme:theme.colorScheme.copyWith(secondary:CinemaColors.accent,
          secondaryContainer:CinemaColors.panel,onSecondaryContainer:CinemaColors.ink),
        textTheme:theme.textTheme.apply(fontFamily:'packages/ismegg/Poppins')),
      home:DesktopHome(prefs:prefs,catalog:catalog));
  }
}

class DesktopHome extends StatefulWidget{
  final SharedPreferences prefs;
  final DesktopCatalog catalog;
  const DesktopHome({super.key,required this.prefs,required this.catalog});
  @override State<DesktopHome> createState()=>_DesktopHomeState();
}
class _DesktopHomeState extends State<DesktopHome>{
  static const storageKey='desktop.saved.v1';
  final search=TextEditingController();
  final searchFocus=FocusNode();
  final scroll=ScrollController();
  final saved=<String,Movie>{};
  final watched=<String,Movie>{};
  DesktopPage page=DesktopPage.home;
  List<Movie> items=[],pinoy=[],korean=[];
  bool loading=true;
  bool picking=false,saving=false;
  int featuredIndex=0;
  String? error;
  int generation=0;
  Timer? debounce;
  static const labels=['Home','Movies','Series','Search','My List'];
  static const icons=[Icons.home_outlined,Icons.movie_outlined,Icons.tv_outlined,
    Icons.search,Icons.bookmark_outline];

  @override void initState(){
    super.initState();
    for(final row in widget.prefs.getStringList(storageKey)??[]){
      try{
        final m=Movie.fromJson(jsonDecode(row) as Map<String,dynamic>);
        if(m.id.isNotEmpty&&m.title.isNotEmpty)saved[m.id]=m;
      }catch(_){}
    }
    readWatched();
    unawaited(loadRegional());
    unawaited(load());
  }
  Future<void> loadRegional()async{
    Future<List<Movie>> read(String name)async{
      try{
        final json=jsonDecode(await rootBundle.loadString('assets/catalogs/$name.json')) as Map<String,dynamic>;
        return CatalogSnapshot.fromJson(json).movies;
      }catch(_){return [];}
    }
    final lists=await Future.wait([read('pinoy'),read('korean')]);
    if(mounted)setState((){pinoy=lists[0];korean=lists[1];});
  }
  void readWatched(){
    watched.clear();
    for(final row in widget.prefs.getStringList('desktop.watched.v1')??[]){
      try{
        final m=Movie.fromJson(jsonDecode(row) as Map<String,dynamic>);
        if(m.id.isNotEmpty&&m.title.isNotEmpty)watched[m.id]=m;
      }catch(_){}
    }
  }
  @override void dispose(){
    debounce?.cancel();
    search.dispose();searchFocus.dispose();scroll.dispose();
    widget.catalog.close();
    super.dispose();
  }
  Future<void> load()async{
    final request=++generation;
    if(page==DesktopPage.saved){
      setState((){loading=false;error=null;items=saved.values.toList();});
      return;
    }
    final q=page==DesktopPage.search?search.text.trim():'';
    setState((){loading=true;error=null;items=[];});
    try{
      final result=await widget.catalog.browse(page,query:q);
      if(mounted&&request==generation)setState((){items=result;loading=false;});
    }catch(_){
      if(mounted&&request==generation)setState((){error='Could not load the catalog. Check your connection and try again.';loading=false;});
    }
  }
  void navigate(DesktopPage next){
    debounce?.cancel();
    if(scroll.hasClients)scroll.jumpTo(0);
    setState((){page=next;featuredIndex=0;});
    unawaited(load());
    if(next==DesktopPage.search){
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&page==next)searchFocus.requestFocus();});
    }else{searchFocus.unfocus();}
  }
  void searchChanged(String value){
    debounce?.cancel();
    ++generation;
    setState((){items=[];loading=value.trim().isNotEmpty;error=null;});
    debounce=Timer(const Duration(milliseconds:350),()=>unawaited(load()));
  }
  Future<void> toggleSaved(Movie movie)async{
    if(saving)return;
    saving=true;
    final wasSaved=saved.containsKey(movie.id);
    final updated=Map<String,Movie>.of(saved);
    if(wasSaved){updated.remove(movie.id);}else{updated[movie.id]=movie;}
    try{
      if(!await widget.prefs.setStringList(storageKey,updated.values.map((m)=>jsonEncode(m.toJson())).toList())){
        throw StateError('Save failed');
      }
      if(!mounted)return;
      setState((){
        saved..clear()..addAll(updated);
        if(page==DesktopPage.saved)items=saved.values.toList();
      });
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not save your list.')));
    }finally{saving=false;}
  }
  Future<void> openVideo()async{
    if(picking)return;
    picking=true;
    try{
      final file=await openFile(acceptedTypeGroups:const [
        XTypeGroup(label:'Video files',extensions:['mp4','mkv','webm','mov','avi','m4v','ts']),
      ]);
      if(file==null||!mounted)return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>DesktopLocalPlayer(path:file.path)));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open a video file.')));
    }finally{picking=false;}
  }
  Future<void> play(Movie movie,{String episode=''})async{
    if(!DesktopNativeEngine.available){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Prepare the native desktop engine to watch online.')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>
      DesktopStreamPlayer(movie:movie,prefs:widget.prefs,episode:episode)));
    if(mounted)setState(readWatched);
  }
  Future<void> details(Movie m)async{
    await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>DesktopTitlePage(
      movie:m,initialSaved:saved.containsKey(m.id),catalog:widget.catalog,
      onSave:()=>toggleSaved(m),onPlay:(episode)=>play(m,episode:episode))));
  }
  Widget poster(Movie m)=>DesktopPoster(key:ValueKey(m.id),movie:m,saved:saved.containsKey(m.id),
    onOpen:()=>unawaited(details(m)),onSave:()=>unawaited(toggleSaved(m)));
  Widget cinematicHome(){
    final candidates=items.where((m)=>m.backdrop.isNotEmpty).take(6).toList();
    final featured=candidates.isEmpty?items.first:candidates[featuredIndex%candidates.length];
    final movies=items.where((m)=>!m.episodic&&m.id!=featured.id).toList();
    final series=items.where((m)=>m.episodic&&m.id!=featured.id).toList();
    final resume=watched.values.toList();
    return CustomScrollView(controller:scroll,slivers:[
      SliverToBoxAdapter(child:LayoutBuilder(builder:(context,box)=>CinemaScene(
        movie:featured,height:(box.maxWidth*.40).clamp(430.0,720.0).toDouble(),saved:saved.containsKey(featured.id),
        onSave:()=>unawaited(toggleSaved(featured)),onDetails:()=>unawaited(details(featured)),
        onPlay:DesktopNativeEngine.available&&!featured.episodic?()=>unawaited(play(featured)):null,
        footer:candidates.length>1?Row(mainAxisSize:MainAxisSize.min,children:[
          IconButton(tooltip:'Previous feature',onPressed:()=>setState(()=>featuredIndex=(featuredIndex+candidates.length-1)%candidates.length),icon:const Icon(Icons.chevron_left)),
          Text('${featuredIndex%candidates.length+1} / ${candidates.length}',style:const TextStyle(color:CinemaColors.muted)),
          IconButton(tooltip:'Next feature',onPressed:()=>setState(()=>featuredIndex=(featuredIndex+1)%candidates.length),icon:const Icon(Icons.chevron_right)),
        ]):null,
      ))),
      SliverToBoxAdapter(child:CinemaShelf(title:'Continue watching',movies:resume,poster:(m)=>DesktopPoster(
        movie:m,saved:saved.containsKey(m.id),onSave:()=>unawaited(toggleSaved(m)),
        onOpen:(){
          final episode=widget.prefs.getString('desktop.lastEpisode.${m.id}')??'';
          if(DesktopNativeEngine.available&&(!m.episodic||episode.isNotEmpty)){
            unawaited(play(m,episode:episode));
          }else{unawaited(details(m));}
        }))),
      SliverToBoxAdapter(child:CinemaShelf(title:'Discover movies',movies:movies,poster:poster)),
      SliverToBoxAdapter(child:CinemaShelf(title:'Series to explore',movies:series,poster:poster)),
      SliverToBoxAdapter(child:CinemaShelf(title:'Filipino cinema',movies:pinoy,poster:poster)),
      SliverToBoxAdapter(child:CinemaShelf(title:'Korean cinema',movies:korean,poster:poster)),
      SliverToBoxAdapter(child:CinemaShelf(title:'My List',movies:saved.values.toList(),poster:poster)),
    ]);
  }

  @override Widget build(BuildContext context)=>CallbackShortcuts(
    bindings:{
      const SingleActivator(LogicalKeyboardKey.keyK,control:true):()=>navigate(DesktopPage.search),
      const SingleActivator(LogicalKeyboardKey.keyO,control:true):()=>unawaited(openVideo()),
      const SingleActivator(LogicalKeyboardKey.keyR,control:true):()=>unawaited(load()),
    },
    child:Focus(autofocus:true,child:Scaffold(body:SafeArea(child:LayoutBuilder(builder:(context,box){
      final expanded=box.maxWidth>=1000;
      return Row(children:[
        SizedBox(width:expanded?224:76,child:ColoredBox(color:CinemaColors.panel,child:Column(children:[
          Padding(padding:const EdgeInsets.symmetric(vertical:24),child:Text.rich(TextSpan(
            style:TextStyle(fontSize:expanded?26:16,fontWeight:FontWeight.w800),
            children:[const TextSpan(text:'isme'),if(expanded)const TextSpan(text:'.gg',style:TextStyle(color:CinemaColors.accent))]))),
          Expanded(child:ListView(padding:const EdgeInsets.symmetric(horizontal:8),children:[
            for(var i=0;i<labels.length;i++)Padding(padding:const EdgeInsets.symmetric(vertical:3),
              child:expanded?ListTile(
                contentPadding:const EdgeInsets.symmetric(horizontal:14),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
                leading:Icon(icons[i],color:page.index==i?CinemaColors.accent:CinemaColors.muted),
                title:Text(labels[i],maxLines:1),
                selected:page.index==i,selectedTileColor:CinemaColors.canvas,
                onTap:()=>navigate(DesktopPage.values[i])):
                IconButton(tooltip:labels[i],isSelected:page.index==i,
                  onPressed:()=>navigate(DesktopPage.values[i]),
                  icon:Icon(icons[i]),selectedIcon:Icon(icons[i],color:CinemaColors.accent))),
          ])),
          if(expanded)const Padding(padding:EdgeInsets.all(16),child:Text('Desktop preview',style:TextStyle(color:CinemaColors.muted,fontSize:12))),
        ]))),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.fromLTRB(24,20,24,12),child:Wrap(
            alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,
            spacing:12,runSpacing:10,children:[
              Text(labels[page.index],style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.w700)),
              FilledButton.icon(onPressed:()=>unawaited(openVideo()),icon:const Icon(Icons.folder_open),
                label:const Text('Open file')),
            ])),
          if(page==DesktopPage.search)Padding(padding:const EdgeInsets.fromLTRB(24,0,24,12),child:TextField(
            focusNode:searchFocus,controller:search,onChanged:searchChanged,
            decoration:const InputDecoration(hintText:'Search movies and series',prefixIcon:Icon(Icons.search)))),
          if(page!=DesktopPage.home)Padding(padding:const EdgeInsets.fromLTRB(24,0,24,16),child:Text(
            page==DesktopPage.saved?'Saved on this computer.': 'Find your next favorite.',
            style:const TextStyle(color:CinemaColors.muted,fontSize:12))),
          Expanded(child:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(
            padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
              Text(error!,textAlign:TextAlign.center),const SizedBox(height:12),
              OutlinedButton(onPressed:()=>unawaited(load()),child:const Text('Retry')),
            ]))):items.isEmpty?Center(child:Text(page==DesktopPage.saved?'Your list is empty.':
              page==DesktopPage.search&&search.text.trim().isEmpty?'Search for a title.':'No titles found.')):
              page==DesktopPage.home?cinematicHome():GridView.builder(
                controller:scroll,padding:const EdgeInsets.fromLTRB(24,0,24,24),
                gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent:234,mainAxisSpacing:24,crossAxisSpacing:20,childAspectRatio:.59),
                itemCount:items.length,itemBuilder:(context,i){
                  return poster(items[i]);
                }),
            ),
          ],
        )),
      ]);
    })))));
}

class DesktopPoster extends StatefulWidget{
  final Movie movie;
  final bool saved;
  final VoidCallback onOpen,onSave;
  const DesktopPoster({super.key,required this.movie,required this.saved,required this.onOpen,required this.onSave});
  @override State<DesktopPoster> createState()=>_DesktopPosterState();
}
class _DesktopPosterState extends State<DesktopPoster>{
  bool hovered=false,focused=false,saveFocused=false;
  @override Widget build(BuildContext context){
    final motion=MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:160);
    final active=hovered||focused||saveFocused;
    return MouseRegion(cursor:SystemMouseCursors.click,onEnter:(_)=>setState(()=>hovered=true),
      onExit:(_)=>setState(()=>hovered=false),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:Stack(fit:StackFit.expand,children:[
          FocusableActionDetector(
            onFocusChange:(v)=>setState(()=>focused=v),
            shortcuts:const {SingleActivator(LogicalKeyboardKey.enter):ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space):ActivateIntent()},
            actions:{ActivateIntent:CallbackAction<ActivateIntent>(onInvoke:(_){widget.onOpen();return null;})},
            child:Semantics(button:true,label:widget.movie.title,child:GestureDetector(
              onTap:widget.onOpen,child:AnimatedContainer(duration:motion,padding:const EdgeInsets.all(2),
                decoration:BoxDecoration(border:Border.all(color:active?CinemaColors.accent:Colors.transparent,width:2),
                  borderRadius:BorderRadius.circular(8)),
                child:ClipRRect(borderRadius:BorderRadius.circular(5),child:AnimatedScale(
                  duration:motion,scale:active&&!MediaQuery.disableAnimationsOf(context)?1.035:1,
                  child:CinemaArt(widget.movie.poster))))))),
          Positioned(top:8,right:8,child:AnimatedOpacity(
            duration:motion,opacity:active||widget.saved?1:0,
            child:Focus(onFocusChange:(v)=>setState(()=>saveFocused=v),skipTraversal:true,
              child:IconButton(tooltip:widget.saved?'Remove from My List':'Add to My List',
              style:IconButton.styleFrom(backgroundColor:CinemaColors.canvas.withValues(alpha:.85),
                foregroundColor:widget.saved?CinemaColors.accent:CinemaColors.ink),
              onPressed:widget.onSave,icon:Icon(widget.saved?Icons.bookmark:Icons.bookmark_border))))),
        ])),
        const SizedBox(height:7),
        Text(widget.movie.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600)),
        Text(widget.movie.year.isEmpty?widget.movie.type:widget.movie.year,maxLines:1,
          overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,color:CinemaColors.muted)),
      ]));
  }
}
