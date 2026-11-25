import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design.dart';
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
  @override void dispose(){debounce?.cancel();search.dispose();homeScroll.dispose();selected.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final tv=engine.tv;
    return Scaffold(body:SafeArea(child:Column(children:[
      Padding(padding:EdgeInsets.symmetric(horizontal:tv?40:16,vertical:10),child:Row(children:[
        const Wordmark(),const Spacer(),
        TextButton(onPressed:()=>setState(()=>searching=false),child:Text('Home',style:TextStyle(color:!searching?CinemaColors.accent:CinemaColors.ink))),
        TextButton(onPressed:()=>setState(()=>searching=true),child:Text('Search',style:TextStyle(color:searching?CinemaColors.accent:CinemaColors.ink))),
        PopupMenuButton<String>(onSelected:(v)async{if(v=='source'){await manual();}else if(v=='refresh'){await load();}else{try{await engine.checkUpdates();}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Updates not configured in this development build.')));}}},itemBuilder:(_)=>const [PopupMenuItem(value:'source',child:Text('Open source')),PopupMenuItem(value:'refresh',child:Text('Refresh catalog')),PopupMenuItem(value:'update',child:Text('Check updates'))])
      ])),
      Expanded(child:searching?buildSearch(tv):buildHome(tv))
    ])));
  }
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
  Widget shelf(String name,List<Movie> movies,bool tv)=>Padding(padding:const EdgeInsets.only(bottom:22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Padding(padding:EdgeInsets.symmetric(horizontal:tv?40:16),child:Text(name,style:TextStyle(fontSize:tv?22:19,fontWeight:FontWeight.w700))),
    const SizedBox(height:10),
    SizedBox(height:tv?204:175,child:ListView.builder(scrollDirection:Axis.horizontal,padding:EdgeInsets.symmetric(horizontal:tv?40:16),itemCount:movies.length,itemBuilder:(_,i)=>Padding(padding:const EdgeInsets.only(right:10),child:SizedBox(width:tv?132:112,child:poster(movies[i],tv)))))
  ]));
  Widget buildHome(bool tv)=>Stack(children:[
    if(tv) Positioned.fill(child:ValueListenableBuilder<Movie?>(valueListenable:selected,builder:(_,m,__)=>m==null?const SizedBox():Stack(fit:StackFit.expand,children:[
      Align(alignment:Alignment.topRight,child:SizedBox(width:MediaQuery.sizeOf(context).width*.82,height:MediaQuery.sizeOf(context).height*.72,child:CinemaArt(m.art,cacheWidth:1280))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[CinemaColors.canvas,Color(0xAA11110F),Colors.transparent],stops:[0,.42,1]))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.canvas],stops:[.20,.76])))
    ]))),
    CustomScrollView(controller:homeScroll,slivers:[
      SliverToBoxAdapter(child:ValueListenableBuilder<Movie?>(valueListenable:selected,builder:(_,m,__)=>m==null?const SizedBox(height:16):hero(m,tv))),
      if(loading)const SliverToBoxAdapter(child:LinearProgressIndicator()),
      if(widget.history.movies().isNotEmpty)SliverToBoxAdapter(child:shelf('Continue watching',widget.history.movies(),tv)),
      for(final entry in collections.entries)
        if(shelves[entry.key]?.isNotEmpty==true)SliverToBoxAdapter(child:shelf(entry.value,shelves[entry.key]!,tv))
        else if(failures.containsKey(entry.key))SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.all(16),child:TextButton(onPressed:load,child:Text('Retry ${entry.value}'))))
    ])
  ]);
  Widget hero(Movie m,bool tv)=>SizedBox(height:tv?270:340,child:Stack(fit:StackFit.expand,children:[
    if(!tv)...[CinemaArt(m.art,cacheWidth:900),const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.canvas])))],
    Padding(padding:EdgeInsets.fromLTRB(tv?40:16,24,16,16),child:Align(alignment:Alignment.bottomLeft,child:ConstrainedBox(constraints:BoxConstraints(maxWidth:tv?440:340),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(m.title,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?42:32,height:1.05,fontWeight:FontWeight.w800)),
      if(m.year.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(m.year,style:const TextStyle(color:CinemaColors.muted))),
      if(tv)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(m.description,maxLines:2,overflow:TextOverflow.ellipsis)),
      const SizedBox(height:14),FilledButton.icon(onPressed:()=>open(m),icon:const Icon(Icons.play_arrow),label:const Text('Watch'))
    ]))))
  ]));
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
