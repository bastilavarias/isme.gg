import 'dart:async';
import 'package:flutter/material.dart';
import '../design.dart';
import '../engine.dart';
import '../platform_rail.dart';
import '../player.dart';
import 'mobile_details.dart';
import 'mobile_library.dart';
import 'mobile_widgets.dart';

class MobileHome extends StatefulWidget{
  final NativeEngine engine;
  final History history;
  const MobileHome({super.key,required this.engine,required this.history});
  @override State<MobileHome> createState()=>_MobileHomeState();
}
class _MobileHomeState extends State<MobileHome>{
  static const categories=['All','Movies','TV Series','Anime','Pinoy'];
  static const baseRows={
    'trending':'Trending movies','series':'Popular TV series','anime':'Popular anime',
    'pinoy':'Filipino movies','korean':'Korean movies','action':'Action movies','horror':'Horror movies',
  };
  final shelves=<String,List<Movie>>{};
  final failures=<String>{};
  final homeScroll=ScrollController(),searchScroll=ScrollController(),browseScroll=ScrollController(),libraryScroll=ScrollController();
  final query=TextEditingController();
  final searchFocus=FocusNode();
  final pageStorage=PageStorageBucket();
  late final MobileLibrary library;
  List<WatchProvider> directory=[],artwork=[];
  PlatformBrand platform=PlatformBrand.all;
  String category='All',searchCategory='All';
  List<Movie> results=[];
  List<String> recent=[];
  int tab=0,revision=0,searchRevision=0,directoryRevision=0;
  bool busy=true,searching=false,platformBusy=false,searchFailed=false,opening=false;
  Timer? debounce;
  NativeEngine get engine=>widget.engine;
  bool get filtered=>platform.key!='all';

  Map<String,String> get rows{
    if(filtered){
      final p=platform.matches(directory),movie=p.any((x)=>x.movie),tv=p.any((x)=>x.tv);
      final films=movie&&(category=='All'||category=='Movies');
      final shows=tv&&(category=='All'||category=='TV Series');
      final anime=tv&&(category=='Anime'||(category=='All'&&platform.key=='crunchyroll'));
      return {
        if(films)'movie:popular':'Popular movies',
        if(shows)'tv:popular':'Popular TV series',
        if(anime)'tv:anime':'Popular anime',
        if(films)'movie:recent':'Recently released movies',
        if(shows)'tv:recent':'Recently released series',
        if(films)'movie:rated':'Top rated movies',
        if(shows)'tv:rated':'Top rated series',
      };
    }
    return switch(category){
      'Movies'=>{'trending':'Trending movies','english':'English movies','action':'Action','horror':'Horror','scifi':'Sci-fi','top_rated':'Top rated'},
      'TV Series'=>{'series':'Popular TV series','series_rated':'Top rated series'},
      'Anime'=>{'anime':'Popular anime','anime_rated':'Top rated anime'},
      'Pinoy'=>{'pinoy':'Filipino movies',if(engine.providersConfigured)'series_pinoy':'Filipino TV series'},
      _=>baseRows,
    };
  }
  @override void initState(){
    super.initState();library=MobileLibrary(widget.history);
    recent=widget.history.prefs.getStringList('isme-mobile-searches')??[];
    unawaited(load());unawaited(loadDirectory());
  }
  @override void dispose(){
    revision++;searchRevision++;directoryRevision++;debounce?.cancel();
    for(final s in [homeScroll,searchScroll,browseScroll,libraryScroll]){s.dispose();}
    query.dispose();searchFocus.dispose();super.dispose();
  }
  Future<void> loadDirectory({bool refresh=false}) async{
    final n=++directoryRevision;
    setState(()=>platformBusy=true);
    try{
      final cached=await engine.watchPlatforms(mode:'cached');
      if(!mounted||n!=directoryRevision)return;
      if(cached.isNotEmpty)setState(()=>directory=cached);
      final data=await engine.watchPlatforms(mode:refresh?'refresh':'normal');
      if(!mounted||n!=directoryRevision)return;
      setState(()=>directory=data);
    }catch(_){}
    finally{if(mounted&&n==directoryRevision)setState(()=>platformBusy=false);}
    if(!mounted||n!=directoryRevision)return;
    if(filtered)unawaited(load(refresh:refresh));
    try{
      final cached=await engine.watchPlatforms(mode:'cached',artworkOnly:true);
      if(!mounted||n!=directoryRevision)return;
      if(cached.isNotEmpty)setState(()=>artwork=cached);
      final data=await engine.watchPlatforms(artworkOnly:true);
      if(mounted&&n==directoryRevision)setState(()=>artwork=data);
    }catch(_){}
  }
  Future<void> load({bool refresh=false}) async{
    final n=++revision,requested=Map<String,String>.of(rows);
    final brand=platform,providers=List<WatchProvider>.of(directory);
    bool current()=>mounted&&revision==n;
    setState((){busy=true;failures.clear();shelves.removeWhere((key,_)=>!requested.containsKey(key));});
    Future<CatalogSnapshot> snapshot(String key,String mode){
      if(brand.key=='all')return engine.catalogSnapshot(key,mode:mode);
      final parts=key.split(':');
      final ids=brand.matches(providers).where((p)=>parts[0]=='movie'?p.movie:p.tv).map((p)=>p.id).toList();
      return engine.platformCatalog(ids,parts[0],parts[1],mode:mode);
    }
    // Bound live fan-out to two rows at a time; cache renders independently.
    final keys=requested.keys.toList();
    for(var i=0;i<keys.length;i+=2){
      if(!current())return;
      await Future.wait(keys.skip(i).take(2).map((key)async{
        CatalogSnapshot? saved;
        try{
          saved=await snapshot(key,'cached');
          if(current()&&saved.movies.isNotEmpty){final items=saved.movies;setState(()=>shelves[key]=category=='TV Series'?items.where((m)=>m.type=='Series').toList():items);}
        }catch(_){}
        if(!current()||(!refresh&&saved?.cacheHit==true&&saved?.stale==false))return;
        try{
          final data=await snapshot(key,refresh?'refresh':'normal');
          if(current())setState(()=>shelves[key]=category=='TV Series'?data.movies.where((m)=>m.type=='Series').toList():data.movies);
        }catch(_){if(current()&&shelves[key]?.isNotEmpty!=true)setState(()=>failures.add(key));}
      }));
    }
    if(current())setState(()=>busy=false);
  }
  Future<void> refresh() async{
    if(filtered){await loadDirectory(refresh:true);}
    else{await load(refresh:true);unawaited(loadDirectory(refresh:true));}
  }
  void setCategory(String value){
    if(category==value&&tab==0)return;
    setState((){
      if(value!=category)shelves.clear();
      category=value;tab=0;
      if(value=='Pinoy'){platform=PlatformBrand.all;}
    });
    if(homeScroll.hasClients)homeScroll.jumpTo(0);
    unawaited(load());
  }
  void selectPlatform(PlatformBrand brand){
    if(platform.key==brand.key&&tab==0)return;
    setState((){
      if(brand.key!=platform.key)shelves.clear();
      platform=brand;tab=0;
      if(category=='Pinoy')category='All';
    });
    if(homeScroll.hasClients)homeScroll.jumpTo(0);
    unawaited(load());
  }
  List<Movie> unique(Iterable<Movie> items,{int limit=100}){
    final seen=<String>{};
    return items.where((m)=>seen.add(m.id)).take(limit).toList();
  }
  List<Movie> get popular=>unique(shelves.values.expand((m)=>m),limit:30);
  List<Movie> get searchItems{
    final items=query.text.trim().isEmpty?popular:results;
    return items.where((m)=>switch(searchCategory){
      'Movies'=>!m.episodic,'TV Series'=>m.type=='Series','Anime'=>m.type=='Anime',_=>true,
    }).toList();
  }
  void search(String value){
    debounce?.cancel();
    final n=++searchRevision,term=value.trim();
    final needle=term.toLowerCase();
    setState((){
      searching=term.isNotEmpty;searchFailed=false;
      results=term.isEmpty?[]:unique([...shelves.values.expand((x)=>x),...library.saved.values,...library.recent].where((m)=>m.title.toLowerCase().contains(needle)));
    });
    if(term.isEmpty)return;
    debounce=Timer(const Duration(milliseconds:350),()async{
      var success=false;
      await Future.wait(['trending','series'].map((key)async{
        try{
          final data=await engine.catalog(key,query:term);
          success=true;
          if(mounted&&n==searchRevision)setState(()=>results=unique([...results,...data]));
        }catch(_){}
      }));
      if(mounted&&n==searchRevision)setState((){searching=false;searchFailed=!success;});
    });
  }
  void rememberSearch(){
    final value=query.text.trim();
    if(value.isEmpty)return;
    setState(()=>recent=[value,...recent.where((s)=>s!=value)].take(8).toList());
    unawaited(widget.history.prefs.setStringList('isme-mobile-searches',recent));
  }
  Future<void> open(Movie movie) async{
    if(opening)return;
    opening=true;
    FocusManager.instance.primaryFocus?.unfocus();
    if(tab==1)rememberSearch();
    try{
      final resolved=await engine.identifyMovie(movie);
      if(!mounted)return;
      await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>resolved.isEpisode?CinemaPlayer(movie:resolved,engine:engine,history:widget.history):MobileDetails(movie:resolved,engine:engine,library:library)));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Title details are unavailable.')));}
    finally{opening=false;if(mounted)setState((){});}
  }
  void seeAll(String title,List<Movie> movies){
    Navigator.of(context).push(MaterialPageRoute(builder:(_)=>Scaffold(
      appBar:AppBar(title:Text(title)),body:SafeArea(child:MobileGrid(movies:movies,engine:engine,onOpen:open)))));
  }
  Future<void> metadataSettings() async{
    final country=TextEditingController(text:engine.providerCountry),token=TextEditingController();
    String? error;
    final value=await showModalBottomSheet<Map<String,String>>(context:context,isScrollControlled:true,showDragHandle:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>SafeArea(
      child:SingleChildScrollView(padding:EdgeInsets.fromLTRB(20,8,20,20+MediaQuery.viewInsetsOf(ctx).bottom),child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Text('Streaming availability',style:TextStyle(fontSize:22,fontWeight:FontWeight.w700)),
          const SizedBox(height:8),const Text('Connect TMDB for live regional platform catalogs. Your token is encrypted on this device.'),
          const SizedBox(height:16),
          TextField(controller:country,maxLength:2,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Country code')),
          TextField(controller:token,obscureText:true,enableSuggestions:false,autocorrect:false,decoration:InputDecoration(labelText:'TMDB read token',helperText:engine.providersConfigured?'Leave blank to keep the saved token':null)),
          if(error!=null)Text(error!,style:const TextStyle(color:CinemaColors.accent)),
          const SizedBox(height:12),
          FilledButton(onPressed:(){
            final code=country.text.trim().toUpperCase(),value=token.text.trim();
            if(!RegExp(r'^[A-Z]{2}$').hasMatch(code)||value.length>2048||(value.isNotEmpty&&!RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(value))){update(()=>error='Check the country and token.');return;}
            Navigator.pop(ctx,{'country':code,if(value.isNotEmpty)'token':value});
          },child:const Text('Save')),
          TextButton(onPressed:()=>Navigator.pop(ctx,{'country':engine.providerCountry,'token':''}),child:const Text('Clear token')),
        ])))));
    // A sheet can animate after its result completes; defer disposing controllers.
    Future<void>.delayed(const Duration(milliseconds:400),(){country.dispose();token.dispose();});
    if(!mounted||value==null)return;
    await widget.history.prefs.setString('isme-provider-country',value['country']!);
    if(!mounted)return;
    try{await engine.configureMetadata(value['country']!,value['token']);}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Token could not be saved on this device.')));}
    if(!mounted)return;
    revision++;directoryRevision++;
    setState((){directory=[];artwork=[];shelves.clear();});
    await loadDirectory(refresh:true);
    if(mounted&&!filtered)await load(refresh:true);
  }
  void settings(){
    showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const ListTile(title:Text('Settings',style:TextStyle(fontSize:21,fontWeight:FontWeight.w700))),
      ListTile(leading:const Icon(Icons.public),title:const Text('Streaming availability'),subtitle:Text(engine.providerCountry),onTap:(){Navigator.pop(ctx);metadataSettings();}),
      StatefulBuilder(builder:(ctx,update)=>SwitchListTile(secondary:const Icon(Icons.skip_next),title:const Text('Autoplay next episode'),
        value:widget.history.prefs.getBool('isme-autoplay-next')??true,onChanged:(v)async{await widget.history.prefs.setBool('isme-autoplay-next',v);if(ctx.mounted)update((){});})),
      ListTile(leading:const Icon(Icons.refresh),title:const Text('Refresh catalogs'),onTap:(){Navigator.pop(ctx);refresh();}),
      ListTile(leading:const Icon(Icons.system_update),title:const Text('Check for updates'),onTap:()async{
        Navigator.pop(ctx);
        try{await engine.checkUpdates();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Updates are not configured for this build.')));}
      }),
      const Padding(padding:EdgeInsets.all(16),child:Text('Metadata and artwork: TMDB · Availability: JustWatch',style:TextStyle(fontSize:11,color:CinemaColors.muted))),
    ])));
  }
  Widget chips(List<String> labels,String selected,ValueChanged<String> onChanged)=>SingleChildScrollView(scrollDirection:Axis.horizontal,
    padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[
      for(final label in labels)Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(label),selected:label==selected,
        onSelected:(_)=>onChanged(label),showCheckmark:false,labelStyle:TextStyle(color:label==selected?CinemaColors.accent:CinemaColors.ink,fontSize:12),
        selectedColor:const Color(0x333F3124),side:BorderSide(color:label==selected?CinemaColors.accent:const Color(0x335F5A55)))),
    ]));
  Widget heading(String title,{VoidCallback? all})=>Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[
    Expanded(child:Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w700))),
    if(all!=null)TextButton(onPressed:all,child:const Text('See all',style:TextStyle(fontSize:12))),
  ]));
  Widget shelf(String title,List<Movie> items)=>Padding(padding:const EdgeInsets.only(bottom:18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    heading(title,all:()=>seeAll(title,items)),
    const SizedBox(height:5),
    LayoutBuilder(builder:(ctx,box){
      final width=(box.maxWidth/3.35).clamp(92.0,142.0).toDouble();
      return SizedBox(height:width*1.5+23,child:ListView.separated(
        key:PageStorageKey('mobile-$category-${platform.key}-$title'),scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:16),itemCount:items.length,
        separatorBuilder:(_,__)=>const SizedBox(width:10),
        itemBuilder:(_,i)=>SizedBox(width:width,child:MobilePoster(movie:items[i],engine:engine,onTap:()=>open(items[i])))));
    }),
  ]));
  Widget resumeShelf(){
    final items=library.recent;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      heading('Continue watching',all:(){setState(()=>tab=3);}),
      const SizedBox(height:6),
      SizedBox(height:130,child:ListView.separated(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:16),
        itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(width:10),itemBuilder:(_,i){
          final m=items[i],progress=library.fraction(items[i]);
          return SizedBox(width:158,child:InkWell(onTap:()=>open(m),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            AspectRatio(aspectRatio:16/9,child:ClipRRect(borderRadius:BorderRadius.circular(8),child:Stack(fit:StackFit.expand,children:[
              CinemaArt(m.art,cacheWidth:480),const Center(child:Icon(Icons.play_circle_outline,size:32)),
              if(progress!=null)Align(alignment:Alignment.bottomCenter,child:LinearProgressIndicator(value:progress,minHeight:3)),
            ]))),
            const SizedBox(height:5),Text(m.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12)),
            Text('${library.history.position(m).inMinutes} min watched',style:const TextStyle(fontSize:10,color:CinemaColors.muted)),
          ])));
        })),
    ]);
  }
  Widget platforms()=>PlatformRail(providers:[...directory,...artwork],selected:platform,onSelected:selectPlatform,onUp:(){},onDown:(){},tv:false);
  Widget home(){
    final featured=unique(rows.keys.expand((k)=>shelves[k]??[]),limit:4);
    return RefreshIndicator(onRefresh:refresh,child:CustomScrollView(key:const PageStorageKey('mobile-home'),controller:homeScroll,physics:const AlwaysScrollableScrollPhysics(),slivers:[
      SliverToBoxAdapter(child:chips(categories,category,setCategory)),
      if(featured.isNotEmpty)SliverToBoxAdapter(child:_Featured(key:PageStorageKey('$category:${platform.key}'),movies:featured,onOpen:open)),
      if(busy)const SliverToBoxAdapter(child:LinearProgressIndicator(minHeight:2)),
      SliverToBoxAdapter(child:platforms()),
      if(library.recent.isNotEmpty)SliverToBoxAdapter(child:resumeShelf()),
      if(filtered)SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,4,16,12),child:Row(children:[
        Expanded(child:Text('Explore ${platform.name}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700))),
        TextButton(onPressed:()=>selectPlatform(PlatformBrand.all),child:const Text('Clear')),
      ]))),
      if(!busy&&featured.isEmpty)SliverToBoxAdapter(child:MobileEmpty(
        filtered?'No titles available':'Nothing to show yet',
        filtered&&!engine.providersConfigured?'Connect TMDB in settings to browse this platform.':platformBusy?'Loading availability…':'Try refreshing, or choose another collection.',
        retry:filtered&&!engine.providersConfigured?metadataSettings:refresh)),
      for(final entry in rows.entries)
        if(shelves[entry.key]?.isNotEmpty==true)SliverToBoxAdapter(child:shelf(entry.value,shelves[entry.key]!))
        else if(failures.contains(entry.key))SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextButton(onPressed:refresh,child:Text('Retry ${entry.value}')))),
      const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(16),child:Text('Metadata and artwork: TMDB · Availability: JustWatch',style:TextStyle(fontSize:10,color:CinemaColors.muted)))),
    ]));
  }
  Widget searchPage()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Padding(padding:const EdgeInsets.fromLTRB(16,8,16,8),child:TextField(
      focusNode:searchFocus,controller:query,onChanged:search,onSubmitted:(_)=>rememberSearch(),textInputAction:TextInputAction.search,
      decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Movies, series, anime…',
        suffixIcon:IconButton(tooltip:'Clear search',onPressed:(){query.clear();search('');},icon:const Icon(Icons.close))))),
    chips(categories.take(4).toList(),searchCategory,(v)=>setState(()=>searchCategory=v)),
    if(query.text.trim().isEmpty&&recent.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Wrap(spacing:8,children:[
      for(final value in recent.take(4))ActionChip(label:Text(value,maxLines:1,overflow:TextOverflow.ellipsis),onPressed:(){query.text=value;search(value);}),
    ])),
    if(searching)const LinearProgressIndicator(minHeight:2),
    if(query.text.trim().isEmpty)heading('Popular titles'),
    Expanded(child:searchItems.isEmpty?MobileEmpty(searching?'Searching…':'No titles found',
      searchFailed?'Search unavailable. Try again.':'Try another title or category.'):MobileGrid(movies:searchItems,engine:engine,onOpen:open,controller:searchScroll)),
  ]);
  Widget browse()=>CustomScrollView(key:const PageStorageKey('mobile-browse'),controller:browseScroll,slivers:[
    const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(16),child:Text('Browse by category',style:TextStyle(fontSize:22,fontWeight:FontWeight.w700)))),
    SliverPadding(padding:const EdgeInsets.symmetric(horizontal:16),sliver:SliverGrid(
      gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:220,mainAxisExtent:74,crossAxisSpacing:10,mainAxisSpacing:10),
      delegate:SliverChildListDelegate([
        for(final name in categories.skip(1))OutlinedButton(onPressed:()=>setCategory(name),child:Text(name)),
        for(final genre in ['Action','Horror','Sci-fi','Korean movies'])OutlinedButton(onPressed:()async{
          final key=switch(genre){'Action'=>'action','Horror'=>'horror','Sci-fi'=>'scifi',_=>'korean'};
          try{final items=await engine.catalog(key);if(mounted)seeAll(genre,items);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Collection unavailable.')));}
        },child:Text(genre)),
      ]))),
    const SliverToBoxAdapter(child:SizedBox(height:24)),
    SliverToBoxAdapter(child:platforms()),
  ]);
  Widget myList()=>CustomScrollView(key:const PageStorageKey('mobile-library'),controller:libraryScroll,slivers:[
    if(library.recent.isNotEmpty)SliverToBoxAdapter(child:resumeShelf()),
    SliverToBoxAdapter(child:heading('Saved titles')),
    if(library.saved.isEmpty)const SliverToBoxAdapter(child:MobileEmpty('Your list is empty','Save a title from its details page to find it here.')),
    SliverPadding(padding:const EdgeInsets.all(16),sliver:SliverGrid(
      gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:150,childAspectRatio:.60,crossAxisSpacing:10,mainAxisSpacing:12),
      delegate:SliverChildBuilderDelegate((ctx,i){
        final m=library.saved.values.elementAt(i);
        return MobilePoster(movie:m,engine:engine,onTap:()=>open(m));
      },childCount:library.saved.length))),
  ]);
  @override Widget build(BuildContext context){
    final size=MediaQuery.sizeOf(context);
    final landscape=size.width>size.height&&size.height>=300;
    final page=switch(tab){1=>searchPage(),2=>browse(),3=>myList(),_=>home()};
    final destinations=const [
      NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Home'),
      NavigationDestination(icon:Icon(Icons.search),label:'Search'),
      NavigationDestination(icon:Icon(Icons.grid_view_outlined),label:'Browse'),
      NavigationDestination(icon:Icon(Icons.bookmark_border),selectedIcon:Icon(Icons.bookmark),label:'My List'),
    ];
    void changeTab(int i){
      FocusManager.instance.primaryFocus?.unfocus();
      setState(()=>tab=i);
    }
    final content=Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,2,8,2),child:Row(children:[
        Expanded(child:tab==0?const Text.rich(TextSpan(style:TextStyle(fontSize:27,fontWeight:FontWeight.w800,letterSpacing:-1),children:[
          TextSpan(text:'isme'),TextSpan(text:'.',style:TextStyle(color:CinemaColors.accent)),TextSpan(text:'gg'),
        ])):Text(['Home','Search','Browse','My List'][tab],style:const TextStyle(fontSize:24,fontWeight:FontWeight.w700))),
        IconButton(tooltip:'Settings',onPressed:settings,icon:const Icon(Icons.settings_outlined)),
      ])),
      Expanded(child:PageStorage(bucket:pageStorage,child:KeyedSubtree(key:ValueKey(tab),child:page))),
    ]);
    return Scaffold(
      body:SafeArea(child:landscape?Row(children:[
        NavigationRail(selectedIndex:tab,onDestinationSelected:changeTab,backgroundColor:CinemaColors.canvas,labelType:NavigationRailLabelType.all,
          destinations:[for(final d in destinations)NavigationRailDestination(icon:d.icon,selectedIcon:d.selectedIcon,label:Text(d.label))]),
        Expanded(child:content),
      ]):content),
      bottomNavigationBar:landscape||MediaQuery.viewInsetsOf(context).bottom>0?null:NavigationBar(
        selectedIndex:tab,onDestinationSelected:changeTab,height:66,backgroundColor:CinemaColors.canvas,
        indicatorColor:const Color(0x333F3124),destinations:destinations),
    );
  }
}
class _Featured extends StatefulWidget{
  final List<Movie> movies;
  final ValueChanged<Movie> onOpen;
  const _Featured({super.key,required this.movies,required this.onOpen});
  @override State<_Featured> createState()=>_FeaturedState();
}
class _FeaturedState extends State<_Featured>{
  final controller=PageController();int index=0;
  @override void didUpdateWidget(covariant _Featured old){
    super.didUpdateWidget(old);
    if(index>=widget.movies.length){
      index=0;WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&controller.hasClients)controller.jumpToPage(0);});
    }
  }
  @override void dispose(){controller.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final size=MediaQuery.sizeOf(context),landscape=size.width>size.height;
    final height=(size.height*(landscape ? .64 : .43)).clamp(210.0,370.0).toDouble();
    return Padding(padding:const EdgeInsets.fromLTRB(16,12,16,12),child:Column(children:[
      SizedBox(height:height,child:ClipRRect(borderRadius:BorderRadius.circular(12),child:PageView.builder(
        controller:controller,itemCount:widget.movies.length,onPageChanged:(i)=>setState(()=>index=i),itemBuilder:(ctx,i){
          final m=widget.movies[i];
          return Stack(fit:StackFit.expand,children:[
            CinemaArt(m.art,cacheWidth:960),
            const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,
              colors:[Colors.transparent,Color(0x22000000),Color(0xEE11110F)],stops:[0,.35,1]))),
            Align(alignment:Alignment.bottomLeft,child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(m.title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:27,fontWeight:FontWeight.w800,height:1.1)),
              const SizedBox(height:6),Text(m.metadata,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:CinemaColors.muted,fontSize:11)),
              const SizedBox(height:12),FilledButton.icon(onPressed:()=>widget.onOpen(m),icon:const Icon(Icons.play_arrow),label:Text(m.episodic?'Episodes':'Watch now')),
            ]))),
          ]);
        }))),
      const SizedBox(height:9),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        for(var i=0;i<widget.movies.length;i++)Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:AnimatedContainer(
          duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:180),
          width:i==index?15:5,height:5,decoration:BoxDecoration(borderRadius:BorderRadius.circular(4),color:i==index?CinemaColors.accent:CinemaColors.muted))),
      ]),
    ]));
  }
}
