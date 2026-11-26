import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design.dart';
import 'cinema_shelf.dart';
import 'engine.dart';
import 'player.dart';
import 'platform_pill.dart';
import 'search_page.dart';
import 'series_page.dart';
import 'platform_rail.dart';
import 'mobile/mobile_home.dart';
import 'support_menu.dart';
import 'home_sections.dart';
import 'category_catalog.dart';

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
    try {await e.connect(); await e.restoreMetadataCredential(); final h=History(await SharedPreferences.getInstance());final country=h.prefs.getString('isme-provider-country')??'PH';if(RegExp(r'^[A-Z]{2}$').hasMatch(country))e.providerCountry=country;if(!mounted){e.dispose();return;}setState((){engine=e;history=h;error=null;});}
    catch(err){e.dispose();if(mounted)setState(()=>error=err.toString());}
  }
  @override void dispose(){engine?.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,theme:cinemaTheme(),title:'isme.gg',
    home:engine==null?Scaffold(body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Wordmark(size:48),const SizedBox(height:24),
      if(error==null)const CircularProgressIndicator() else ...[Text(error!),TextButton(onPressed:(){setState(()=>error=null);boot();},child:const Text('Retry'))]
    ]))):deviceHome(engine!,history!));
}
/// Device classification comes from Android's UI mode, not screen orientation.
Widget deviceHome(NativeEngine engine,History history)=>engine.tv?CinemaHome(engine:engine,history:history):MobileHome(engine:engine,history:history);
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
  String section='Home';
  final verifiedWeekly=<String>{};
  String? featuredId;
  bool get mainHome=>section=='Home'&&!filtered;
  PlatformBrand platform=PlatformBrand.all;
  List<WatchProvider> platformDirectory=[],platformArtwork=[];
  final platformStatusFocus=FocusNode(debugLabel:'Platform catalog action');
  bool platformBusy=false;
  int platformGeneration=0;
  String? platformError;
  bool get filtered=>section=='Home'&&platform.key!='all';
  final platformRailKey=GlobalKey<PlatformRailState>();
  Map<String,String> get collections{
    if(filtered){
      final prefix='platform:${platform.key}:';
      final matching=platform.matches(platformDirectory);
      final movies=matching.any((p)=>p.movie),tv=matching.any((p)=>p.tv);
      return {
        if(tv&&platform.key=='crunchyroll')'${prefix}tv:anime':'Popular anime',
        if(movies)'${prefix}movie:popular':'Popular movies',
        if(tv&&platform.key!='crunchyroll')'${prefix}tv:popular':'Popular series',
        if(movies)'${prefix}movie:recent':'Recently released movies',
        if(tv)'${prefix}tv:recent':'Recently released series',
        if(movies)'${prefix}movie:rated':'Top rated movies',
        if(tv)'${prefix}tv:rated':'Top rated series',
      };
    }
    return categorySections(section,verifiedWeekly);
  }
  Future<CatalogSnapshot> shelfSnapshot(String key,{String mode='normal'}) async {
    if(!key.startsWith('platform:'))return engine.catalogSnapshot(key,mode:mode);
    final parts=key.split(':');
    final brand=PlatformBrand.brands.firstWhere((p)=>p.key==parts[1]);
    final kind=parts[2],row=parts[3];
    final ids=brand.matches(platformDirectory).where((p)=>kind=='movie'?p.movie:p.tv).map((p)=>p.id).toList();
    return engine.platformCatalog(ids,kind,row,mode:mode);
  }
  Future<void> loadPlatforms({bool force=false}) async {
    final run=++platformGeneration;
    setState((){platformBusy=true;platformError=null;});
    try{
      final cached=await engine.watchPlatforms(mode:'cached');
      if(!mounted||run!=platformGeneration)return;
      if(cached.isNotEmpty)setState(()=>platformDirectory=cached);
      final live=await engine.watchPlatforms(mode:force?'refresh':'normal');
      if(!mounted||run!=platformGeneration)return;
      setState(()=>platformDirectory=live);
    }catch(_){
      if(mounted&&run==platformGeneration)setState(()=>platformError='Platform listings could not refresh.');
    }finally{
      if(mounted&&run==platformGeneration)setState(()=>platformBusy=false);
    }
    if(mounted&&run==platformGeneration&&filtered)await load(force:force);
    // Artwork for services not available locally is fetched separately; it
    // cannot turn a global logo into a regional availability claim.
    if(!mounted||run!=platformGeneration)return;
    try{
      final artwork=await engine.watchPlatforms(artworkOnly:true,mode:'cached');
      if(!mounted||run!=platformGeneration)return;
      if(artwork.isNotEmpty)setState(()=>platformArtwork=artwork);
      final live=await engine.watchPlatforms(artworkOnly:true,mode:'normal');
      if(mounted&&run==platformGeneration)setState(()=>platformArtwork=live);
    }catch(_){}
  }
  void selectPlatform(PlatformBrand next){
    if(platform.key==next.key)return;
    catalogGeneration++;
    setState((){
      platform=next;failures.clear();
      // SQLite retains recent platform results; keep only the selected
      // platform's shelves in the Dart heap.
      shelves.removeWhere((key,_)=>key.startsWith('platform:')&&!key.startsWith('platform:${next.key}:'));
    });
    selected.value=collections.keys.expand((k)=>shelves[k]??<Movie>[]).firstOrNull;
    scrollTop();load();
  }
  void focusFirstShelf(){
    final rows=visibleRows;
    if(rows.isNotEmpty)rowKeys[rows.first]?.currentState?.focusRemembered();
    else if(platformStatusFocus.context!=null)platformStatusFocus.requestFocus();
    else if(mainHome)platformRailKey.currentState?.focusRemembered();
  }
  List<Movie> get continued=>widget.history.movies().where((m)=>belongsToCategory(m,section,
    shelves.values.expand((row)=>row))).toList();
  final shelves=<String,List<Movie>>{}, failures=<String,String>{};
  final selected=ValueNotifier<Movie?>(null);
  final search=TextEditingController();
  final homeScroll=ScrollController(keepScrollOffset:false);
  final homeNav=FocusNode(debugLabel:'Home'), searchNav=FocusNode(debugLabel:'Search'),
    menuNav=FocusNode(debugLabel:'Menu'), heroFocus=FocusNode(debugLabel:'Hero watch');
  final movieNav=FocusNode(debugLabel:'Movies'),seriesNav=FocusNode(debugLabel:'TV Series'),animeNav=FocusNode(debugLabel:'Anime'),pinoyNav=FocusNode(debugLabel:'Pinoy');
  FocusNode get sectionNav=>switch(section){'Movies'=>movieNav,'Series'=>seriesNav,'Anime'=>animeNav,'Pinoy'=>pinoyNav,_=>homeNav};
  final rowKeys=<String,GlobalKey<CinemaShelfState>>{};
  final menuAnchor=GlobalKey();
  final searchPageKey=GlobalKey<CinemaSearchPageState>();
  List<String> get visibleRows=>[
    if(continued.isNotEmpty)'Continue watching',
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
    if(i<0){if(filtered){platformRailKey.currentState?.focusRemembered();}else{focusHero();}return;}
    if(i<rows.length){rowKeys[rows[i]]?.currentState?.focusRemembered();}
    else if(mainHome){platformRailKey.currentState?.focusRemembered();}
    else if(platformStatusFocus.context!=null){platformStatusFocus.requestFocus();}
  }
  void focusHero(){
    scrollTop();
    if(heroFocus.context!=null){heroFocus.requestFocus();}
    else if(filtered){platformRailKey.currentState?.focusRemembered();}
    else if(visibleRows.isNotEmpty||platformStatusFocus.context!=null){focusFirstShelf();}
    else if(mainHome){platformRailKey.currentState?.focusRemembered();}
    else{sectionNav.requestFocus();}
  }
  KeyEventResult navKeys(FocusNode node,KeyEvent event){
    if(!engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    final key=event.logicalKey;
    if(key==LogicalKeyboardKey.select||key==LogicalKeyboardKey.enter||key==LogicalKeyboardKey.numpadEnter){
      if(event is! KeyDownEvent)return KeyEventResult.handled;
      if(homeNav.hasFocus){showSection('Home');return KeyEventResult.handled;}
      if(movieNav.hasFocus){showSection('Movies');return KeyEventResult.handled;}
      if(seriesNav.hasFocus){showSection('Series');return KeyEventResult.handled;}
      if(animeNav.hasFocus){showSection('Anime');return KeyEventResult.handled;}
      if(pinoyNav.hasFocus){showSection('Pinoy');return KeyEventResult.handled;}
      if(searchNav.hasFocus){showSearch();return KeyEventResult.handled;}
      if(menuNav.hasFocus){openNavMenu();return KeyEventResult.handled;}
    }
    if(key==LogicalKeyboardKey.arrowDown){
      if(searching){searchPageKey.currentState?.focusKeyboard();}
      else{focusHero();}
      return KeyEventResult.handled;
    }
    if(key==LogicalKeyboardKey.arrowLeft||key==LogicalKeyboardKey.arrowRight){
      final nodes=[homeNav,searchNav,movieNav,seriesNav,animeNav,pinoyNav,menuNav];
      final current=nodes.indexWhere((n)=>n.hasFocus);
      if(current>=0){nodes[(current+(key==LogicalKeyboardKey.arrowRight?1:-1)).clamp(0,nodes.length-1).toInt()].requestFocus();return KeyEventResult.handled;}
    }
    return KeyEventResult.ignored;
  }
  KeyEventResult heroKeys(FocusNode node,KeyEvent event){
    if(!engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){sectionNav.requestFocus();scrollTop();return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowDown){
      if(filtered){platformRailKey.currentState?.focusRemembered();}else{focusFirstShelf();}
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  Timer? debounce;int generation=0, catalogGeneration=0;bool searching=false;bool loading=true;bool searchBusy=false;List<Movie> results=[];String? searchError;
  NativeEngine get engine=>widget.engine;
  @override void initState(){super.initState();load();loadPlatforms();}
  Future<void> load({bool force=false}) async {
    final run=++catalogGeneration;
    final requested=Map<String,String>.of(collections);
    bool current()=>mounted&&run==catalogGeneration;
    void apply(String key,CatalogSnapshot snapshot){
      if(!current())return;
      final items=filtered?snapshot.movies:sectionMovies(key,snapshot);
      final row=rowKeys[collections[key]]?.currentState;
      // Keep the focused rail stable while an API refresh finishes.
      if(row?.hasActiveFocus==true&&shelves[key]?.isNotEmpty==true)return;
      setState((){if(!filtered)rememberWeekly(verifiedWeekly,key,snapshot);shelves[key]=items;});
      if(selected.value!=null&&!collections.keys.any((k)=>shelves[k]?.any((m)=>m.id==selected.value!.id)==true)&&
        !rowKeys.values.any((k)=>k.currentState?.hasActiveFocus==true)){
        selected.value=collections.keys.expand((k)=>shelves[k]??<Movie>[]).firstOrNull;
      }
      if(selected.value==null&&items.isNotEmpty)selected.value=items.first;
    }
    setState((){loading=true;failures.clear();shelves.removeWhere((key,_)=>!requested.containsKey(key));});
    final keys=requested.keys.toList();
    // Paint all available cached shelves before waiting on network requests.
    final saved=<String,CatalogSnapshot>{};
    for(var i=0;i<keys.length;i+=4){
      if(!current())return;
      await Future.wait(keys.skip(i).take(4).map((key)async{
        try{
          final cached=await shelfSnapshot(key,mode:'cached');
          if(!current())return;
          saved[key]=cached;
          if(cached.movies.isNotEmpty)apply(key,cached);
        }catch(_){}
      }));
    }
    // Keep native network fan-out bounded; generation checks reject stale results.
    for(var i=0;i<keys.length;i+=2){
      if(!current())return;
      await Future.wait(keys.skip(i).take(2).map((key)async{
        if(!current()||(!force&&saved[key]?.cacheHit==true&&saved[key]?.stale==false))return;
        try{
          final live=await shelfSnapshot(key,mode:force?'refresh':'normal');
          if(current())apply(key,live);
        }catch(_){
          if(current()&&shelves[key]?.isNotEmpty!=true)setState(()=>failures[key]='Could not load this collection');
        }
      }));
    }
    if(current()){
      setState(()=>loading=false);
      if(!filtered&&!heroFocus.hasFocus&&!rowKeys.values.any((k)=>k.currentState?.hasActiveFocus==true)){
        final picks=featuredToday(collections.keys.expand((key)=>shelves[key]??<Movie>[]));
        if(picks.isNotEmpty){featuredId=picks.first.id;selected.value=picks.first;}
      }
    }
  }
  List<Movie> uniqueMovies(Iterable<Movie> movies,{int limit=100}){
    final seen=<String>{};
    return movies.where((m)=>seen.add(m.id)).take(limit).toList();
  }
  List<Movie> get popularMovies=>uniqueMovies(collections.keys.expand((key)=>shelves[key]??<Movie>[]),limit:30);
  List<Movie> localMatches(String text){
    final needle=text.trim().toLowerCase();
    if(needle.isEmpty)return [];
    final movies=uniqueMovies([
      ...widget.history.movies(),...shelves.values.expand((row)=>row),
    ],limit:1000).where((m)=>m.title.toLowerCase().contains(needle)).toList();
    // Exact and prefix matches lead, preserving catalog order within each group.
    int rank(Movie m)=>m.title.toLowerCase()==needle?0:m.title.toLowerCase().startsWith(needle)?1:2;
    return [for(int r=0;r<3;r++)...movies.where((m)=>rank(m)==r)].take(50).toList();
  }
  void query(String text){
    debounce?.cancel();final n=++generation;
    final needle=text.trim();
    setState((){searchBusy=needle.isNotEmpty;searchError=null;results=localMatches(needle);});
    if(needle.isEmpty)return;
    debounce=Timer(const Duration(milliseconds:350),()async{
      try{
        bool succeeded=false;
        await Future.wait(['trending','series'].map((collection)async{
          try{
            final items=await engine.catalog(collection,query:needle);
            succeeded=true;
            if(mounted&&n==generation)setState(()=>results=uniqueMovies([...results,...localMatches(needle),...items]));
          }catch(_){}
        }));
        if(!succeeded)throw StateError('Search unavailable');
      }catch(_){if(mounted&&n==generation){
        final saved=uniqueMovies([...results,...localMatches(needle)]);
        setState((){results=saved;searchError=saved.isEmpty?'Search unavailable. Try again.':'Showing saved catalog results';});
      }}
      finally{if(mounted&&n==generation)setState(()=>searchBusy=false);}
    });
  }
  void showSection(String name){
    if(!searching&&section==name&&!filtered){scrollTop();return;}
    catalogGeneration++;
    if(homeScroll.hasClients)homeScroll.jumpTo(0);
    setState((){
      section=name;searching=false;platform=PlatformBrand.all;
      failures.clear();rowKeys.clear();featuredId=null;loading=true;
      shelves.removeWhere((key,_)=>!collections.containsKey(key));
    });
    selected.value=collections.keys.expand((k)=>shelves[k]??<Movie>[]).firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&!searching&&section==name){
        if(homeScroll.hasClients)homeScroll.jumpTo(0);
        sectionNav.requestFocus();
      }
    });
    load();
  }
  void showSearch(){
    setState(()=>searching=true);
    if(engine.tv)WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&searching)searchPageKey.currentState?.focusKeyboard();
    });
  }
  Future<void> open(Movie m) async {
    if(m.id.startsWith('tmdb:movie:')){
      try{m=await engine.identifyMovie(m);}catch(_){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Movie details unavailable. Check your metadata connection.')));
        return;
      }
      if(!mounted)return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>m.isEpisode?CinemaPlayer(movie:m,engine:engine,history:widget.history):m.episodic?SeriesPage(show:m,engine:engine,history:widget.history):Details(movie:m,engine:engine,history:widget.history)));
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
  @override void dispose(){debounce?.cancel();search.dispose();homeScroll.dispose();selected.dispose();homeNav.dispose();movieNav.dispose();seriesNav.dispose();animeNav.dispose();pinoyNav.dispose();searchNav.dispose();menuNav.dispose();heroFocus.dispose();platformStatusFocus.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final tv=engine.tv;
    final nav=Focus(canRequestFocus:false,onKeyEvent:navKeys,child:Container(
      decoration:tv?const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xF0000000),Color(0xB0000000),Colors.transparent])):null,
      padding:EdgeInsets.symmetric(horizontal:tv?40:16,vertical:10),
      child:Row(children:[
        if(tv)const SizedBox(width:100,child:Wordmark()),
        Expanded(child:Center(child:SingleChildScrollView(scrollDirection:Axis.horizontal,
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            navButton('Home',homeNav,!searching&&section=='Home',()=>showSection('Home')),
            navButton('Search',searchNav,searching,showSearch,icon:Icons.search_rounded),
            navDivider(),
            navButton('Movies',movieNav,!searching&&section=='Movies',()=>showSection('Movies')),
            navButton('TV Series',seriesNav,!searching&&section=='Series',()=>showSection('Series')),
            navButton('Anime',animeNav,!searching&&section=='Anime',()=>showSection('Anime')),
            navDivider(),
            navButton('Pinoy',pinoyNav,!searching&&section=='Pinoy',()=>showSection('Pinoy')),
          ])))),
        SizedBox(width:tv?100:40,child:Align(alignment:Alignment.centerRight,child:IconButton(key:menuAnchor,focusNode:menuNav,tooltip:'Menu',onPressed:openNavMenu,icon:const Icon(Icons.more_vert))))
      ])));
    return Scaffold(body:SafeArea(child:Shortcuts(shortcuts:const {
      SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter):ActivateIntent(),
    },child:Stack(children:[
      if(tv&&!searching)Positioned.fill(child:ambient()),
      Positioned.fill(child:Column(children:[
        nav,
        Expanded(child:searching?buildSearch(tv):KeyedSubtree(key:ValueKey('catalog:$section:${platform.key}'),child:buildHome(tv)))
      ]))
    ]))));
  }
  Future<void> openNavMenu() async {
    final anchor=menuAnchor.currentContext?.findRenderObject();
    final overlay=Navigator.of(context).overlay?.context.findRenderObject();
    if(anchor is! RenderBox||overlay is! RenderBox)return;
    final origin=anchor.localToGlobal(Offset.zero,ancestor:overlay);
    final rect=origin & anchor.size;
    await openSupportMenu(context,engine,()=>showMenu<SupportAction>(context:context,
      position:RelativeRect.fromRect(rect,Offset.zero & overlay.size),
      constraints:const BoxConstraints(minWidth:270,maxWidth:340),
      items:supportMenuItems(engine)));
    if(mounted)menuNav.requestFocus();
  }
  Future<void> providerSettings() async {
    final region=TextEditingController(text:engine.providerCountry);
    final token=TextEditingController();
    String? validation;
    final value=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
      title:const Text('Streaming availability'),
      content:SingleChildScrollView(child:SizedBox(width:390,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Connect TMDB for TV series, anime, episode artwork and regional streaming badges.'),
        const SizedBox(height:12),
        TextField(controller:region,maxLength:2,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Country code (e.g. PH, US)')),
        TextField(controller:token,obscureText:true,enableSuggestions:false,autocorrect:false,decoration:const InputDecoration(labelText:'TMDB API read access token')),
        const SizedBox(height:8),
        Text(engine.providersConfigured?'A read token is configured. Leave the field blank to keep it.':'Enter a TMDB API read token once to enable live platform browsing.'),
        const Text('Your token is encrypted on this device using Android Keystore. Data from JustWatch via TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.',style:TextStyle(fontSize:12,color:CinemaColors.muted)),
        if(validation!=null)Text(validation!,style:const TextStyle(color:CinemaColors.accent)),
      ]))),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(ctx,{'country':engine.providerCountry,'token':''}),child:const Text('Clear token')),
        FilledButton(onPressed:(){
          final code=region.text.trim().toUpperCase(),readToken=token.text.trim();
          if(!RegExp(r'^[A-Z]{2}$').hasMatch(code)||readToken.length>2048||(readToken.isNotEmpty&&!RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(readToken))){update(()=>validation='Enter a valid country code and read token.');return;}
          Navigator.pop(ctx,{'country':code,if(readToken.isNotEmpty)'token':readToken});
        },child:const Text('Apply')),
      ],
    )));
    region.dispose();token.dispose();
    if(!mounted||value==null)return;
    final country=value['country']!;
    await widget.history.prefs.setString('isme-provider-country',country);
    if(!mounted)return;
    try{await engine.configureMetadata(country,value['token']);}catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Token is active for this session but could not be saved.')));
    }
    if(!mounted)return;
    catalogGeneration++;
    setState((){
      platformDirectory=[];
      shelves.removeWhere((key,_)=>key.startsWith('platform:'));
      failures.clear();
    });
    selected.value=null;
    menuNav.requestFocus();
    await loadPlatforms(force:true);
    if(mounted&&!filtered)await load(force:true);
    if(mounted&&searching&&search.text.trim().isNotEmpty)query(search.text);
  }
  Widget navDivider()=>Padding(
    padding:EdgeInsets.symmetric(horizontal:engine.tv?9:5),
    child:ExcludeSemantics(child:Container(width:1,height:19,color:const Color(0x26F5F1EB))));
  Widget navButton(String label,FocusNode node,bool active,VoidCallback action,{IconData? icon})=>Builder(builder:(ctx)=>Semantics(
    label:icon!=null?label:null,selected:active,
    child:TextButton(
      key:ValueKey('nav-$label'),focusNode:node,autofocus:label=='Home',onFocusChange:(focused){
        if(!focused)return;
        if(!searching)scrollTop();
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(ctx.mounted&&node.hasFocus)Scrollable.ensureVisible(ctx,duration:motion,curve:Curves.easeOutCubic);
        });
      },
      onPressed:action,style:TextButton.styleFrom(backgroundColor:active?const Color(0x33444444):Colors.transparent,
        foregroundColor:active?CinemaColors.accent:CinemaColors.ink,
        minimumSize:Size(icon!=null?40:0,40),
        padding:EdgeInsets.symmetric(horizontal:engine.tv?10:8,vertical:10)),
      child:icon==null?Text(label,maxLines:1):Tooltip(message:label,child:Icon(icon,size:22)))));
  Widget buildSearch(bool tv)=>CinemaSearchPage(key:searchPageKey,engine:engine,controller:search,
    movies:search.text.trim().isEmpty?popularMovies:results,busy:searchBusy||(search.text.trim().isEmpty&&loading),
    error:searchError,onQuery:query,onOpen:open,onNav:()=>searchNav.requestFocus());
  Widget poster(Movie m,bool tv)=>RemoteTile(label:m.title,onPressed:()=>open(m),onFocused:()=>selected.value=m,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Expanded(child:Stack(fit:StackFit.expand,children:[CinemaArt(m.poster),Positioned(top:5,left:5,child:PlatformPill(engine:engine,movie:m))])),Padding(padding:const EdgeInsets.all(5),child:Text(m.title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?15:12)))
  ]));
  Widget shelf(String name,List<Movie> movies,bool tv)=>tv?CinemaShelf(key:rowKeys.putIfAbsent(name,()=>GlobalKey<CinemaShelfState>()),title:name,movies:movies,engine:engine,ranked:isRankedSection(name),history:name=='Continue watching'?widget.history:null,onHighlight:(m)=>selected.value=m,onOpen:open,onVertical:(down)=>moveRow(name,down),onRowFocus:()=>revealRow(name)):Padding(padding:const EdgeInsets.only(bottom:22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Padding(padding:EdgeInsets.symmetric(horizontal:tv?40:16),child:Text(name,style:TextStyle(fontSize:tv?22:19,fontWeight:FontWeight.w700))),
    const SizedBox(height:10),
    SizedBox(height:tv?204:175,child:ListView.builder(scrollDirection:Axis.horizontal,padding:EdgeInsets.symmetric(horizontal:tv?40:16),itemCount:movies.length,itemBuilder:(_,i)=>Padding(padding:const EdgeInsets.only(right:10),child:SizedBox(width:tv?132:112,child:poster(movies[i],tv)))))
  ]));
  Widget ambient()=>ValueListenableBuilder<Movie?>(valueListenable:selected,builder:(_,m,__)=>m==null?const SizedBox():Stack(fit:StackFit.expand,children:[
      Align(alignment:Alignment.topRight,child:SizedBox(width:MediaQuery.sizeOf(context).width*.88,height:MediaQuery.sizeOf(context).height*.86,child:AnimatedSwitcher(duration:motion,layoutBuilder:(current,previous)=>Stack(fit:StackFit.expand,children:[...previous,if(current!=null)current]),child:CinemaArt(m.art,key:ValueKey(m.art),cacheWidth:1280)))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[CinemaColors.canvas,Color(0xB011110F),Color(0x5511110F)],stops:[0,.42,1]))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.canvas],stops:[.25,.96])))
    ]));
  Widget platformRow(bool tv)=>PlatformRail(key:platformRailKey,providers:[...platformDirectory,...platformArtwork],selected:platform,tv:tv,onSelected:selectPlatform,onUp:(){
    if(mainHome&&visibleRows.isNotEmpty){rowKeys[visibleRows.last]?.currentState?.focusRemembered();}
    else if(heroFocus.context!=null){focusHero();}else{sectionNav.requestFocus();}
  },onDown:(){if(filtered)focusFirstShelf();});
  Widget buildHome(bool tv)=>SingleChildScrollView(key:const ValueKey('tv-home-scroll'),controller:homeScroll,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ValueListenableBuilder<Movie?>(valueListenable:selected,builder:(_,m,__)=>m==null?ConstrainedBox(constraints:BoxConstraints(minHeight:tv?270:200),child:Padding(padding:EdgeInsets.fromLTRB(tv?40:16,28,16,16),child:Align(alignment:Alignment.bottomLeft,child:Text(filtered?platform.name:categoryName(section),key:const ValueKey('tv-catalog-heading'),style:const TextStyle(fontSize:32,fontWeight:FontWeight.w800))))):hero(m,tv)),
      if(loading)const LinearProgressIndicator(minHeight:2),
      if(filtered)platformRow(tv),
      if(continued.isNotEmpty)shelf('Continue watching',continued,tv),
      if(filtered&&!loading&&(collections.isEmpty||!collections.keys.any((k)=>shelves[k]?.isNotEmpty==true)))Padding(
        padding:EdgeInsets.symmetric(horizontal:tv?40:16,vertical:16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(platformBusy?'Loading platforms…':!engine.providersConfigured?'Connect TMDB in settings to explore ${platform.name}.':platformError??'No catalog available for ${platform.name} in ${engine.providerCountry}.',style:const TextStyle(color:CinemaColors.muted)),
          if(!platformBusy)Focus(canRequestFocus:false,onKeyEvent:(_,event){
            if(tv&&event is KeyDownEvent&&event.logicalKey==LogicalKeyboardKey.arrowUp){platformRailKey.currentState?.focusRemembered();return KeyEventResult.handled;}
            return KeyEventResult.ignored;
          },child:TextButton(focusNode:platformStatusFocus,onPressed:engine.providersConfigured?()=>loadPlatforms(force:true):providerSettings,child:Text(engine.providersConfigured?'Refresh platforms':'Metadata settings'))),
        ])),
      for(final entry in collections.entries)
        if(shelves[entry.key]?.isNotEmpty==true)shelf(entry.value,shelves[entry.key]!,tv)
        else if((mainHome||filtered)&&failures.containsKey(entry.key))Padding(padding:const EdgeInsets.all(16),child:TextButton(onPressed:()=>load(force:true),child:Text('Retry ${entry.value}'))),
      if(mainHome)platformRow(tv),
      if(!filtered&&!mainHome&&(!engine.providersConfigured||(!loading&&(failures.isNotEmpty||!collections.keys.any((k)=>shelves[k]?.isNotEmpty==true)))))
        Padding(padding:const EdgeInsets.fromLTRB(40,8,40,28),child:Align(alignment:Alignment.centerLeft,
          child:Focus(canRequestFocus:false,onKeyEvent:(_,event){
            if(event is KeyDownEvent&&event.logicalKey==LogicalKeyboardKey.arrowUp){
              if(visibleRows.isNotEmpty){rowKeys[visibleRows.last]?.currentState?.focusRemembered();}
              else{sectionNav.requestFocus();scrollTop();}
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },child:TextButton(focusNode:platformStatusFocus,
            onPressed:engine.providersConfigured?()=>load(force:true):providerSettings,
            child:Text(engine.providersConfigured?'Retry catalog':'Enable full catalog'))))),
    ]));
  Widget hero(Movie m,bool tv)=>Stack(children:[
    if(!tv) Positioned.fill(child:Stack(fit:StackFit.expand,children:[
      CinemaArt(m.art,cacheWidth:900),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.canvas])))
    ])),
    ConstrainedBox(constraints:BoxConstraints(minHeight:tv?270:340),child:SizedBox(width:double.infinity,
      child:Padding(padding:EdgeInsets.fromLTRB(tv?40:16,24,16,16),child:Align(alignment:Alignment.bottomLeft,heightFactor:1,
        child:ConstrainedBox(constraints:BoxConstraints(maxWidth:tv?440:340),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(!filtered)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(
            m.id==featuredId?categoryFeature(section):categoryName(section).toUpperCase(),
            key:const ValueKey('tv-catalog-heading'),style:const TextStyle(color:CinemaColors.accent,fontSize:12,fontWeight:FontWeight.w700,letterSpacing:1.6))),
          Text(m.title,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?42:32,height:1.05,fontWeight:FontWeight.w800)),
          if(m.metadata.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(m.metadata,style:const TextStyle(color:CinemaColors.muted))),
          if(tv)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(m.description,maxLines:2,overflow:TextOverflow.ellipsis)),
          const SizedBox(height:14),Focus(canRequestFocus:false,onKeyEvent:heroKeys,child:FilledButton.icon(focusNode:heroFocus,onFocusChange:(focused){if(focused&&tv)scrollTop();},onPressed:()=>open(m),icon:const Icon(Icons.play_arrow),label:Text(m.isEpisode?'Resume':m.episodic?'Episodes':'Watch')))
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
