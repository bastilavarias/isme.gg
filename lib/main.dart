import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design.dart';
import 'cinema_shelf.dart';
import 'engine.dart';
import 'player.dart';

void main(){ WidgetsFlutterBinding.ensureInitialized(); PaintingBinding.instance.imageCache.maximumSizeBytes=48*1024*1024; PaintingBinding.instance.imageCache.maximumSize=120; runApp(const IsmeApp()); }
class IsmeApp extends StatefulWidget {
  const IsmeApp({super.key});
  @override State<IsmeApp> createState()=>_IsmeAppState();
}
class _IsmeAppState extends State<IsmeApp> {
  NativeEngine? engine; History? history; String? error;
  @override void initState(){super.initState();boot();}
  Future<void> boot() async {
    final e=NativeEngine();
    try {await e.connect(); final h=History(await SharedPreferences.getInstance());if(!mounted){e.dispose();return;}setState((){engine=e;history=h;error=null;});}
    catch(err){e.dispose();if(mounted)setState(()=>error=err.toString());}
  }
  @override void dispose(){engine?.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,theme:cinemaTheme(),title:'isme.gg',
    home:engine==null?Scaffold(body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Wordmark(size:48),const SizedBox(height:24),
      if(error==null)const CircularProgressIndicator() else ...[Text(error!),TextButton(onPressed:(){setState(()=>error=null);boot();},child:const Text('Retry'))]
    ]))):CinemaHome(engine:engine!,history:history!));
}
class Wordmark extends StatelessWidget {
  final double size;const Wordmark({super.key,this.size=24});
  @override Widget build(BuildContext context)=>Text.rich(TextSpan(style:TextStyle(fontSize:size,fontWeight:FontWeight.w800,letterSpacing:-1.2,color:CinemaColors.ink),children:const [TextSpan(text:'isme'),TextSpan(text:'.',style:TextStyle(color:CinemaColors.accent)),TextSpan(text:'gg')]));
}
class CinemaHome extends StatefulWidget {
  final NativeEngine engine;final History history;
  const CinemaHome({super.key,required this.engine,required this.history});
  @override State<CinemaHome> createState()=>_CinemaHomeState();
}
class _CinemaHomeState extends State<CinemaHome> {
  static const collections={'trending':'Trending now','pinoy':'Filipino movies','korean':'Korean movies','english':'English movies','action':'Action','horror':'Horror'};
  final shelves=<String,List<Movie>>{}, failures=<String,String>{};
  final selected=ValueNotifier<Movie?>(null);
  final search=TextEditingController();
  final homeScroll=ScrollController();
  final homeNav=FocusNode(debugLabel:'Home'), searchNav=FocusNode(debugLabel:'Search'),
    menuNav=FocusNode(debugLabel:'Menu'), heroFocus=FocusNode(debugLabel:'Hero watch');
  final rowKeys=<String,GlobalKey<CinemaShelfState>>{};
  final menuAnchor=GlobalKey();
  List<String> get visibleRows=>[
    if(widget.history.movies().isNotEmpty)'Continue watching',
    for(final entry in collections.entries)if(shelves[entry.key]?.isNotEmpty==true)entry.value,
  ];
  Duration get motion=>MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:300);
  void scrollTop(){
    if(!homeScroll.hasClients)return;
    if(motion==Duration.zero){homeScroll.jumpTo(0);}else{homeScroll.animateTo(0,duration:motion,curve:Curves.easeOutCubic);}
  }
  void revealRow(String name){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(!mounted||searching)return;
      final ctx=rowKeys[name]?.currentContext;
      if(ctx==null||!(rowKeys[name]?.currentState?.hasActiveFocus??false))return;
      Scrollable.ensureVisible(ctx,alignment:0.13,duration:motion,curve:Curves.easeOutCubic);
    });
  }
  void moveRow(String name,bool down){
    final rows=visibleRows;final i=rows.indexOf(name)+(down?1:-1);
    if(i<0){focusHero();return;}
    if(i<rows.length){rowKeys[rows[i]]?.currentState?.focusRemembered();}
  }
  void focusHero(){
    scrollTop();
    if(heroFocus.context!=null){heroFocus.requestFocus();}
    else{homeNav.requestFocus();}
  }
  KeyEventResult navKeys(FocusNode node,KeyEvent event){
    if(!engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    final key=event.logicalKey;
    if(key==LogicalKeyboardKey.arrowDown&&!searching){
      focusHero();return KeyEventResult.handled;
    }
    if(key==LogicalKeyboardKey.arrowLeft||key==LogicalKeyboardKey.arrowRight){
      final nodes=[homeNav,searchNav,menuNav];
      final current=nodes.indexWhere((n)=>n.hasFocus);
      if(current>=0){nodes[(current+(key==LogicalKeyboardKey.arrowRight?1:-1)).clamp(0,2).toInt()].requestFocus();return KeyEventResult.handled;}
    }
    return KeyEventResult.ignored;
  }
  KeyEventResult heroKeys(FocusNode node,KeyEvent event){
    if(!engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){homeNav.requestFocus();scrollTop();return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowDown){
      final rows=visibleRows;if(rows.isNotEmpty)rowKeys[rows.first]?.currentState?.focusRemembered();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  Timer? debounce;int generation=0;bool searching=false;bool loading=true;bool searchBusy=false;List<Movie> results=[];String? searchError;
  NativeEngine get engine=>widget.engine;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    setState((){loading=true;failures.clear();});
    await Future.wait(collections.keys.map((key) async {
      try{final items=await engine.catalog(key);if(!mounted)return;setState(()=>shelves[key]=items);if(key=='trending'&&selected.value==null&&items.isNotEmpty)selected.value=items.first;}
      catch(e){if(mounted)setState(()=>failures[key]='Could not load this collection');}
    }));
    if(mounted){if(selected.value==null){for(final items in shelves.values){if(items.isNotEmpty){selected.value=items.first;break;}}}setState(()=>loading=false);}
  }
  void query(String text){
    debounce?.cancel();final n=++generation;
    setState((){searchBusy=text.trim().isNotEmpty;searchError=null;results=[];});
    if(text.trim().isEmpty)return;
    debounce=Timer(const Duration(milliseconds:350),()async{
      try{final items=await engine.catalog('trending',query:text.trim());if(mounted&&n==generation)setState(()=>results=items);}
      catch(_){if(mounted&&n==generation)setState(()=>searchError='Search unavailable. Try again.');}
      finally{if(mounted&&n==generation)setState(()=>searchBusy=false);}
    });
  }
  Future<void> open(Movie m) async {
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>Details(movie:m,engine:engine,history:widget.history)));
    if(mounted)setState((){});
  }
  Future<void> manual() async {
    final controller=TextEditingController();
    final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Open a permitted media source'),
      content:TextField(controller:controller,autofocus:true,decoration:const InputDecoration(hintText:'magnet:?xt=urn:btih:...')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('Open'))]));
    controller.dispose();
    if(!mounted||value==null||value.isEmpty)return;
    if(!RegExp(r'^magnet:\?xt=urn:btih:[a-fA-F0-9]{40}(?:&.*)?$').hasMatch(value)){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid hexadecimal BTIH magnet.')));return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>CinemaPlayer(movie:const Movie(id:'manual',title:'Media source'),engine:engine,history:widget.history,magnet:value)));
    if(mounted)setState((){});
  }
  @override void dispose(){debounce?.cancel();search.dispose();homeScroll.dispose();selected.dispose();homeNav.dispose();searchNav.dispose();menuNav.dispose();heroFocus.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final tv=engine.tv;
    final nav=Focus(canRequestFocus:false,onKeyEvent:navKeys,child:Container(
      decoration:tv?const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xF0000000),Color(0xB0000000),Colors.transparent])):null,
      padding:EdgeInsets.symmetric(horizontal:tv?40:16,vertical:10),
      child:Stack(alignment:Alignment.center,children:[
        const Align(alignment:Alignment.centerLeft,child:Wordmark()),
        Row(mainAxisSize:MainAxisSize.min,children:[
          navButton('Home',homeNav,!searching,(){setState(()=>searching=false);scrollTop();}),
          const SizedBox(width:8),
          navButton('Search',searchNav,searching,()=>setState(()=>searching=true)),
        ]),
        Align(alignment:Alignment.centerRight,child:IconButton(key:menuAnchor,focusNode:menuNav,tooltip:'Menu',onPressed:openNavMenu,icon:const Icon(Icons.more_vert)))
      ])));
    return Scaffold(body:SafeArea(child:Shortcuts(shortcuts:const {
      SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter):ActivateIntent(),
    },child:Stack(children:[
      if(tv&&!searching)Positioned.fill(child:ambient()),
      Positioned.fill(child:Column(children:[
        nav,
        Expanded(child:searching?buildSearch(tv):buildHome(tv))
      ]))
    ]))));
  }
  Future<void> openNavMenu() async {
    final anchor=menuAnchor.currentContext?.findRenderObject();
    final overlay=Navigator.of(context).overlay?.context.findRenderObject();
    if(anchor is! RenderBox||overlay is! RenderBox)return;
    final origin=anchor.localToGlobal(Offset.zero,ancestor:overlay);
    final rect=origin & anchor.size;
    final v=await showMenu<String>(context:context,
      position:RelativeRect.fromRect(rect,Offset.zero & overlay.size),
      items:const [
        PopupMenuItem(value:'source',child:Text('Open source')),
        PopupMenuItem(value:'refresh',child:Text('Refresh catalog')),
        PopupMenuItem(value:'update',child:Text('Check updates')),
      ]);
    if(!mounted)return;
    menuNav.requestFocus();
    if(v==null)return;
    if(v=='source'){await manual();}
    else if(v=='refresh'){await load();}
    else{
      try{await engine.checkUpdates();}
      catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Updates not configured in this development build.')));}
    }
  }
  Widget navButton(String label,FocusNode node,bool active,VoidCallback action)=>TextButton(
    focusNode:node,onFocusChange:(focused){if(focused&&!searching)scrollTop();},
    onPressed:action,style:TextButton.styleFrom(backgroundColor:active?const Color(0x33444444):Colors.transparent,
      foregroundColor:active?CinemaColors.accent:CinemaColors.ink,padding:const EdgeInsets.symmetric(horizontal:18,vertical:12)),
    child:Text(label));
  Widget buildSearch(bool tv)=>Padding(padding:EdgeInsets.symmetric(horizontal:tv?40:16),child:Column(children:[
    TextField(controller:search,onChanged:query,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Find a movie')),
    const SizedBox(height:16),
    if(searchBusy)const LinearProgressIndicator(),
    if(searchError!=null)Text(searchError!),
    if(!searchBusy&&results.isEmpty&&search.text.isNotEmpty&&searchError==null)const Text('No results'),
    Expanded(child:GridView.builder(gridDelegate:SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:tv?200:150,childAspectRatio:0.65,mainAxisSpacing:10,crossAxisSpacing:10),itemCount:results.length,itemBuilder:(_,i)=>poster(results[i],tv)))
  ]));
  Widget poster(Movie m,bool tv)=>RemoteTile(label:m.title,onPressed:()=>open(m),onFocused:()=>selected.value=m,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Expanded(child:CinemaArt(m.poster)),Padding(padding:const EdgeInsets.all(5),child:Text(m.title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?15:12)))
  ]));
  Widget shelf(String name,List<Movie> movies,bool tv)=>tv?CinemaShelf(key:rowKeys.putIfAbsent(name,()=>GlobalKey<CinemaShelfState>()),title:name,movies:movies,onHighlight:(m)=>selected.value=m,onOpen:open,onVertical:(down)=>moveRow(name,down),onRowFocus:()=>revealRow(name)):Padding(padding:const EdgeInsets.only(bottom:22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Padding(padding:EdgeInsets.symmetric(horizontal:tv?40:16),child:Text(name,style:TextStyle(fontSize:tv?22:19,fontWeight:FontWeight.w700))),
    const SizedBox(height:10),
    SizedBox(height:tv?204:175,child:ListView.builder(scrollDirection:Axis.horizontal,padding:EdgeInsets.symmetric(horizontal:tv?40:16),itemCount:movies.length,itemBuilder:(_,i)=>Padding(padding:const EdgeInsets.only(right:10),child:SizedBox(width:tv?132:112,child:poster(movies[i],tv)))))
  ]));
  Widget ambient()=>ValueListenableBuilder<Movie?>(valueListenable:selected,builder:(_,m,__)=>m==null?const SizedBox():Stack(fit:StackFit.expand,children:[
      Align(alignment:Alignment.topRight,child:SizedBox(width:MediaQuery.sizeOf(context).width*.88,height:MediaQuery.sizeOf(context).height*.86,child:AnimatedSwitcher(duration:motion,layoutBuilder:(current,previous)=>Stack(fit:StackFit.expand,children:[...previous,if(current!=null)current]),child:CinemaArt(m.art,key:ValueKey(m.art),cacheWidth:1280)))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[CinemaColors.canvas,Color(0xB011110F),Color(0x5511110F)],stops:[0,.42,1]))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.canvas],stops:[.25,.96])))
    ]));
  Widget buildHome(bool tv)=>SingleChildScrollView(controller:homeScroll,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ValueListenableBuilder<Movie?>(valueListenable:selected,builder:(_,m,__)=>m==null?const SizedBox(height:16):hero(m,tv)),
      if(loading)const LinearProgressIndicator(),
      if(widget.history.movies().isNotEmpty)shelf('Continue watching',widget.history.movies(),tv),
      for(final entry in collections.entries)
        if(shelves[entry.key]?.isNotEmpty==true)shelf(entry.value,shelves[entry.key]!,tv)
        else if(failures.containsKey(entry.key))Padding(padding:const EdgeInsets.all(16),child:TextButton(onPressed:load,child:Text('Retry ${entry.value}')))
    ]));
  Widget hero(Movie m,bool tv)=>Stack(children:[
    if(!tv) Positioned.fill(child:Stack(fit:StackFit.expand,children:[
      CinemaArt(m.art,cacheWidth:900),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.canvas])))
    ])),
    ConstrainedBox(constraints:BoxConstraints(minHeight:tv?270:340),child:SizedBox(width:double.infinity,
      child:Padding(padding:EdgeInsets.fromLTRB(tv?40:16,24,16,16),child:Align(alignment:Alignment.bottomLeft,heightFactor:1,
        child:ConstrainedBox(constraints:BoxConstraints(maxWidth:tv?440:340),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(m.title,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?42:32,height:1.05,fontWeight:FontWeight.w800)),
          if(m.year.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(m.year,style:const TextStyle(color:CinemaColors.muted))),
          if(tv)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(m.description,maxLines:2,overflow:TextOverflow.ellipsis)),
          const SizedBox(height:14),Focus(canRequestFocus:false,onKeyEvent:heroKeys,child:FilledButton.icon(focusNode:heroFocus,onFocusChange:(focused){if(focused&&tv)scrollTop();},onPressed:()=>open(m),icon:const Icon(Icons.play_arrow),label:const Text('Watch')))
        ]))))))
  ]);
}
class Details extends StatelessWidget {
  final Movie movie;final NativeEngine engine;final History history;
  const Details({super.key,required this.movie,required this.engine,required this.history});
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Stack(fit:StackFit.expand,children:[
    CinemaArt(movie.art,cacheWidth:1280),
    const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0x6611110F),CinemaColors.canvas],stops:[0,.86]))),
    Padding(padding:EdgeInsets.all(engine.tv?40:20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.arrow_back)),
      Expanded(child:Align(alignment:Alignment.bottomLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:650),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(movie.title,style:TextStyle(fontWeight:FontWeight.w800,fontSize:engine.tv?44:34)),const SizedBox(height:8),Text(movie.year),
        const SizedBox(height:12),Text(movie.description,style:const TextStyle(fontSize:16)),const SizedBox(height:22),
        FilledButton.icon(autofocus:true,onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CinemaPlayer(movie:movie,engine:engine,history:history))),icon:const Icon(Icons.play_arrow),label:Text(history.position(movie)>Duration.zero?'Resume':'Play'))
      ])))))
    ]))
  ])));
}
