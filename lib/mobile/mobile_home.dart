import 'dart:async';
import 'package:flutter/material.dart';
import '../design.dart';
import '../my_list.dart';
import '../engine.dart';
import '../platform_rail.dart';
import '../player.dart';
import '../support_menu.dart';
import '../home_sections.dart';
import '../category_catalog.dart';
import '../back_navigation.dart';
import '../next_episode.dart';
import 'mobile_details.dart';
import 'mobile_discovery.dart';
import 'mobile_library.dart';
import 'mobile_widgets.dart';

class MobileHome extends StatefulWidget{
  final NativeEngine engine;
  final History history;
  const MobileHome({super.key,required this.engine,required this.history});
  @override State<MobileHome> createState()=>_MobileHomeState();
}
class _MobileHomeState extends State<MobileHome>{
  static const navigation=['Home','Search','My List'];
  final verifiedWeekly=<String>{};
  bool get mainHome=>category=='Home'&&!filtered;
  final shelves=<String,List<Movie>>{};
  final failures=<String>{};
  final homeScroll=ScrollController(keepScrollOffset:false),searchScroll=ScrollController();
  final query=TextEditingController();
  final searchFocus=FocusNode();
  final pageStorage=PageStorageBucket();
  late final MobileLibrary library;
  List<WatchProvider> directory=[],artwork=[];
  PlatformBrand platform=PlatformBrand.all;
  String category='Home',searchCategory='All';
  List<Movie> results=[];
  List<String> recent=[];
  int tab=0,revision=0,searchRevision=0,directoryRevision=0;
  bool busy=true,searching=false,platformBusy=false,searchFailed=false,opening=false;
  Timer? debounce;
  NativeEngine get engine=>widget.engine;
  bool get filtered=>category=='Home'&&platform.key!='all';

  Map<String,String> get rows{
    if(filtered){
      final p=platform.matches(directory),movie=p.any((x)=>x.movie),tv=p.any((x)=>x.tv);
      return {
        if(tv&&platform.key=='crunchyroll')'tv:anime':'Popular anime',
        if(movie)'movie:popular':'Popular movies',
        if(tv&&platform.key!='crunchyroll')'tv:popular':'Popular series',
        if(movie)'movie:recent':'Recently released movies',
        if(tv)'tv:recent':'Recently released series',
        if(movie)'movie:rated':'Top rated movies',
        if(tv)'tv:rated':'Top rated series',
      };
    }
    return categorySections(category,verifiedWeekly);
  }
  @override void initState(){
    super.initState();library=MobileLibrary(widget.history);
    recent=widget.history.prefs.getStringList('isme-mobile-searches')??[];
    unawaited(load());unawaited(loadDirectory());
  }
  @override void dispose(){
    revision++;searchRevision++;directoryRevision++;debounce?.cancel();
    for(final s in [homeScroll,searchScroll]){s.dispose();}
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
    final brand=filtered?platform:PlatformBrand.all,providers=List<WatchProvider>.of(directory);
    bool current()=>mounted&&revision==n;
    void apply(String key,CatalogSnapshot data){
      if(!current())return;
      setState((){if(!filtered)rememberWeekly(verifiedWeekly,key,data);shelves[key]=filtered?data.movies:sectionMovies(key,data);});
    }
    setState((){busy=true;failures.clear();shelves.removeWhere((key,_)=>!requested.containsKey(key));});
    Future<CatalogSnapshot> snapshot(String key,String mode){
      if(brand.key=='all')return engine.catalogSnapshot(key,mode:mode);
      final parts=key.split(':');
      final ids=brand.matches(providers).where((p)=>parts[0]=='movie'?p.movie:p.tv).map((p)=>p.id).toList();
      return engine.platformCatalog(ids,parts[0],parts[1],mode:mode);
    }
    // Show cached catalog immediately, then load missing/stale rows in pairs.
    final keys=requested.keys.toList();
    final saved=<String,CatalogSnapshot>{};
    for(var i=0;i<keys.length;i+=4){
      if(!current())return;
      await Future.wait(keys.skip(i).take(4).map((key)async{
        try{
          final data=await snapshot(key,'cached');
          if(!current())return;
          saved[key]=data;
          if(data.movies.isNotEmpty)apply(key,data);
        }catch(_){}
      }));
    }
    for(var i=0;i<keys.length;i+=2){
      if(!current())return;
      await Future.wait(keys.skip(i).take(2).map((key)async{
        if(!current()||(!refresh&&saved[key]?.cacheHit==true&&saved[key]?.stale==false))return;
        try{
          final data=await snapshot(key,refresh?'refresh':'normal');
          apply(key,data);
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
    FocusManager.instance.primaryFocus?.unfocus();
    if(category==value&&tab==0&&!filtered){if(homeScroll.hasClients)homeScroll.jumpTo(0);return;}
    revision++;
    if(homeScroll.hasClients)homeScroll.jumpTo(0);
    setState((){
      category=value;tab=0;platform=PlatformBrand.all;busy=true;failures.clear();
      shelves.removeWhere((key,_)=>!rows.containsKey(key));
    });
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&tab==0&&category==value&&homeScroll.hasClients)homeScroll.jumpTo(0);
    });
    unawaited(load());
  }
  void selectPlatform(PlatformBrand brand){
    if(platform.key==brand.key&&tab==0)return;
    setState((){
      if(brand.key!=platform.key)shelves.clear();
      platform=brand;tab=0;
      category='Home';
    });
    if(homeScroll.hasClients)homeScroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&tab==0&&platform.key==brand.key&&homeScroll.hasClients)homeScroll.jumpTo(0);
    });
    unawaited(load());
  }
  List<Movie> unique(Iterable<Movie> items,{int limit=100}){
    final seen=<String>{};
    return items.where((m)=>seen.add(m.id)).take(limit).toList();
  }
  List<Movie> get searchItems{
    return results.where((m)=>switch(searchCategory){
      'Movies'=>!m.episodic,'TV Series'=>m.type=='Series','Anime'=>m.type=='Anime'||m.animeFilm,_=>true,
    }).toList();
  }
  void search(String value){
    debounce?.cancel();
    final n=++searchRevision,term=value.trim();
    final needle=term.toLowerCase();
    setState((){
      searching=term.isNotEmpty;searchFailed=false;
      if(term.isEmpty)searchCategory='All';
      results=term.isEmpty?[]:unique([...shelves.values.expand((x)=>x),...library.recent].where((m)=>m.title.toLowerCase().contains(needle)));
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
  Future<void> open(Movie movie,{BuildContext? routeContext}) async{
    final target=routeContext??context;
    if(opening)return;
    opening=true;
    FocusManager.instance.primaryFocus?.unfocus();
    if(tab==1)rememberSearch();
    try{
      final resolved=await engine.identifyMovie(movie);
      if(!mounted||!target.mounted||ModalRoute.of(target)?.isCurrent!=true)return;
      final episode=EpisodeIdentity.parse(resolved);
      final title=episode?.parent(resolved)??resolved;
      await pushTitleRoute(target,MobileDetails(movie:title,engine:engine,library:library),
        resumePlayer:episode==null?null:CinemaPlayer(movie:resolved,engine:engine,history:widget.history));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Title details are unavailable.')));}
    finally{opening=false;if(mounted)setState((){});}
  }
  Future<void> settings()=>openSupportMenu(context,engine,()=>showSupportSheet(context,engine));
  Widget chips(List<String> labels,String selected,ValueChanged<String> onChanged)=>SingleChildScrollView(scrollDirection:Axis.horizontal,
    padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[
      for(final label in labels)Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(label),selected:label==selected,
        onSelected:(_)=>onChanged(label),showCheckmark:false,labelStyle:TextStyle(color:label==selected?CinemaColors.accent:CinemaColors.ink,fontSize:12),
        selectedColor:const Color(0x333F3124),side:BorderSide(color:label==selected?CinemaColors.accent:const Color(0x335F5A55)))),
    ]));
  Widget heading(String title)=>Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
    child:Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w700)));
  List<Movie> get continued=>library.recent.where((m)=>belongsToCategory(m,category,
    shelves.values.expand((row)=>row))).toList();
  Widget shelf(String title,List<Movie> items)=>Padding(padding:const EdgeInsets.only(bottom:18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    heading(title),
    const SizedBox(height:5),
    LayoutBuilder(builder:(ctx,box){
      final width=(box.maxWidth/3.35).clamp(92.0,142.0).toDouble();
      final ranked=isRankedSection(title);
      return SizedBox(height:width*1.5+23,child:ListView.separated(
        key:PageStorageKey('mobile-$category-${platform.key}-$title'),scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:16),itemCount:items.length,
        separatorBuilder:(_,__)=>const SizedBox(width:10),
        itemBuilder:(_,i)=>SizedBox(width:ranked?width*1.52:width,child:MobilePoster(movie:items[i],engine:engine,rank:ranked?i+1:null,onTap:()=>open(items[i])))));
    }),
  ]));
  Widget resumeShelf(){
    final items=continued;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      heading('Continue watching'),
      const SizedBox(height:6),
      SizedBox(height:130,child:ListView.separated(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:16),
        itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(width:10),itemBuilder:(_,i){
          final m=items[i],progress=library.fraction(items[i]);
          return SizedBox(width:158,child:InkWell(onTap:()=>open(m),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            AspectRatio(aspectRatio:16/9,child:ClipRRect(borderRadius:BorderRadius.circular(8),child:Stack(fit:StackFit.expand,children:[
              CinemaArt(m.art,cacheWidth:480),const Center(child:Icon(Icons.play_circle_outline,size:32)),
              if(progress!=null)Align(alignment:Alignment.bottomCenter,child:LinearProgressIndicator(value:progress,minHeight:3)),
            ]))),
            const SizedBox(height:5),Text(resumeTitle(m),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12)),
            Text('${library.history.position(m).inMinutes} min watched',style:const TextStyle(fontSize:10,color:CinemaColors.muted)),
          ])));
        })),
    ]);
  }
  Widget platforms()=>PlatformRail(providers:[...directory,...artwork],selected:platform,onSelected:selectPlatform,onUp:(){},onDown:(){},tv:false);
  Widget home(){
    final candidates=rows.keys.expand((k)=>shelves[k]??<Movie>[]);
    final picked=filtered?unique(candidates,limit:4):featuredToday(candidates);
    final featured=picked.isEmpty?unique(candidates,limit:4):picked;
    return RefreshIndicator(onRefresh:refresh,child:CustomScrollView(key:const PageStorageKey('mobile-home'),controller:homeScroll,physics:const AlwaysScrollableScrollPhysics(),slivers:[
      if(!filtered&&!mainHome)SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,10,16,0),
        child:Text(category,key:const ValueKey('mobile-catalog-heading'),style:const TextStyle(fontSize:25,fontWeight:FontWeight.w800)))),
      if(featured.isNotEmpty)SliverToBoxAdapter(child:_Featured(key:PageStorageKey('$category:${platform.key}'),movies:featured,onOpen:open,featureLabel:filtered?'':categoryFeature(category))),
      if(busy)const SliverToBoxAdapter(child:LinearProgressIndicator(minHeight:2)),
      if(filtered)SliverToBoxAdapter(child:platforms()),
      if(continued.isNotEmpty)SliverToBoxAdapter(child:resumeShelf()),
      if(filtered)SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,4,16,12),child:Row(children:[
        Expanded(child:Text('Explore ${platform.name}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700))),
        TextButton(onPressed:()=>selectPlatform(PlatformBrand.all),child:const Text('Clear')),
      ]))),
      if(!busy&&featured.isEmpty)SliverToBoxAdapter(child:MobileEmpty(
        filtered?'No titles available':'Nothing to show yet',
        platformBusy?'Loading availability…':'Try refreshing, or choose another collection.',
        retry:refresh)),
      for(final entry in rows.entries)
        if(shelves[entry.key]?.isNotEmpty==true)SliverToBoxAdapter(child:shelf(entry.value,shelves[entry.key]!))
        else if((mainHome||filtered)&&failures.contains(entry.key))SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextButton(onPressed:refresh,child:Text('Retry ${entry.value}')))),
      if(mainHome)SliverToBoxAdapter(child:platforms()),
      if(!filtered&&!mainHome&&!busy&&failures.isNotEmpty)SliverToBoxAdapter(child:Padding(
        padding:const EdgeInsets.fromLTRB(16,8,16,22),child:Align(alignment:Alignment.centerLeft,
          child:TextButton(onPressed:refresh,
            child:const Text('Retry catalog'))))),
    ]));
  }
  void browse(DiscoveryTile tile)=>openDiscovery(tile.name,collections:tile.collections);
  void browsePlatform(PlatformBrand brand){
    if(brand.key!='all')openDiscovery(brand.name,brand:brand);
  }
  Future<void> openDiscovery(String title,{List<String> collections=const [],PlatformBrand? brand}) async{
    searchFocus.unfocus();
    await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>MobileDiscoveryCatalog(
      title:title,engine:engine,collections:collections,brand:brand,providers:directory,
      onOpen:(ctx,movie)=>open(movie,routeContext:ctx))));
  }
  void clearRecent(){
    setState(()=>recent=[]);
    unawaited(widget.history.prefs.remove('isme-mobile-searches'));
  }
  Widget discovery()=>ListView(
    key:const PageStorageKey('mobile-discovery'),
    padding:const EdgeInsets.only(bottom:24),
    children:[
      if(recent.isNotEmpty)...[
        Padding(padding:const EdgeInsets.fromLTRB(16,0,16,0),child:Row(children:[
          const Expanded(child:Text('Recent searches',style:TextStyle(fontSize:19,fontWeight:FontWeight.w700))),
          TextButton(onPressed:clearRecent,child:const Text('Clear')),
        ])),
        Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Wrap(spacing:8,runSpacing:4,children:[
          for(final value in recent.take(4))ActionChip(avatar:const Icon(Icons.history,size:16),
            label:Text(value,maxLines:1,overflow:TextOverflow.ellipsis),onPressed:(){query.text=value;search(value);}),
        ])),
      ],
      heading('Browse categories'),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:DiscoveryGrid(tiles:mobileCategories,onSelected:browse)),
      const SizedBox(height:16),
      heading('Browse genres'),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:DiscoveryGrid(tiles:mobileGenres,onSelected:browse)),
      const SizedBox(height:24),
      PlatformRail(providers:[...directory,...artwork],selected:PlatformBrand.all,onSelected:browsePlatform,onUp:(){},onDown:(){},tv:false),
    ]);
  Widget searchPage(){
    final empty=query.text.trim().isEmpty;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,8,16,8),child:TextField(
        key:const ValueKey('mobile-search-field'),focusNode:searchFocus,controller:query,onChanged:search,
        onSubmitted:(_){rememberSearch();searchFocus.unfocus();},textInputAction:TextInputAction.search,
        decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Movies, series, anime…',
          suffixIcon:empty?null:IconButton(tooltip:'Clear search',onPressed:(){query.clear();search('');searchFocus.unfocus();},icon:const Icon(Icons.close))))),
      if(!empty)chips(const ['All','Movies','TV Series','Anime'],searchCategory,(v)=>setState(()=>searchCategory=v)),
      if(searching)const LinearProgressIndicator(minHeight:2),
      Expanded(child:empty?discovery():searchItems.isEmpty?MobileEmpty(searching?'Searching…':'No titles found',
        searchFailed?'Search unavailable. Try again.':'Try another title or category.'):MobileGrid(movies:searchItems,engine:engine,onOpen:open,controller:searchScroll)),
    ]);
  }
  static const navIcons=<String,IconData>{
    'Home':Icons.home_outlined,
    'Search':Icons.search_rounded,
    'My List':Icons.bookmark_border,
  };
  Widget navItem(String label){
    final active=navigation.indexOf(label)==tab;
    final color=active?CinemaColors.accent:CinemaColors.muted;
    return Semantics(
      selected:active,button:true,label:label,
      child:InkWell(
        key:ValueKey('mobile-nav-$label'),onTap:(){
          if(label=='Home'){setCategory('Home');}
          else if(label=='Search'){showSearch();}
          else{searchFocus.unfocus();setState(()=>tab=2);}
        },
        borderRadius:BorderRadius.circular(12),
        child:ConstrainedBox(constraints:const BoxConstraints(minHeight:54,minWidth:48),
          child:Padding(padding:const EdgeInsets.symmetric(vertical:5,horizontal:2),
            child:Column(mainAxisSize:MainAxisSize.min,mainAxisAlignment:MainAxisAlignment.center,children:[
              AnimatedContainer(
                duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:160),
                padding:const EdgeInsets.symmetric(horizontal:22,vertical:4),
                decoration:BoxDecoration(
                  color:active?const Color(0x22F3A369):Colors.transparent,
                  borderRadius:BorderRadius.circular(16)),
                child:Icon(navIcons[label],size:22,color:color)),
              const SizedBox(height:2),
              Text(label,maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,
                style:TextStyle(fontSize:12,color:color,fontWeight:active?FontWeight.w600:FontWeight.w400)),
            ])))));
  }
  Widget bottomNav()=>Material(
    key:const ValueKey('mobile-bottom-nav'),
    color:CinemaColors.canvas,
    child:SafeArea(top:false,child:DecoratedBox(
      decoration:const BoxDecoration(border:Border(top:BorderSide(color:Color(0x1FFFFFFF)))),
      child:Padding(padding:const EdgeInsets.fromLTRB(4,3,4,3),child:Row(children:[
        for(final label in navigation)Expanded(child:navItem(label)),
      ])))));
  Widget sideNav()=>Material(
    key:const ValueKey('mobile-side-nav'),
    color:CinemaColors.canvas,
    child:Container(width:76,decoration:const BoxDecoration(
      border:Border(right:BorderSide(color:Color(0x1FFFFFFF)))),
      child:ListView(padding:const EdgeInsets.symmetric(horizontal:4,vertical:4),children:[
        for(final label in navigation)navItem(label),
      ])));
  void showSearch(){
    if(tab==1)return;
    searchFocus.unfocus();
    setState(()=>tab=1);
  }
  bool backToHome(){
    if(tab==1&&query.text.trim().isNotEmpty){query.clear();search('');searchFocus.unfocus();return true;}
    if(tab!=0||!mainHome){setCategory('Home');return true;}
    return false;
  }
  @override Widget build(BuildContext context){
    final page=tab==2?MyList(store:widget.history.bookmarks,engine:engine,onOpen:(ctx,movie)=>open(movie,routeContext:ctx)):tab==1?searchPage():home();
    final landscape=MediaQuery.orientationOf(context)==Orientation.landscape;
    final keyboard=MediaQuery.viewInsetsOf(context).bottom>0;
    final content=Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,2,8,2),child:Row(children:[
        const Expanded(child:Text.rich(TextSpan(style:TextStyle(fontSize:26,fontWeight:FontWeight.w800,letterSpacing:-1),children:[
          TextSpan(text:'isme'),TextSpan(text:'.',style:TextStyle(color:CinemaColors.accent)),TextSpan(text:'gg'),
        ]))),
        IconButton(tooltip:'Menu',onPressed:settings,icon:const Icon(Icons.more_vert)),
      ])),
      Expanded(child:PageStorage(bucket:pageStorage,child:KeyedSubtree(key:ValueKey('$tab:$category:${platform.key}'),child:page))),
    ]);
    return HomeBackGuard(locationKey:'$tab:$category:${platform.key}',navigateHome:backToHome,
      child:Scaffold(
      body:SafeArea(bottom:landscape||keyboard,child:Row(children:[
        if(landscape&&!keyboard)sideNav(),
        Expanded(child:content),
      ])),
      bottomNavigationBar:landscape||keyboard?null:bottomNav(),
    ));
  }
}
class _Featured extends StatefulWidget{
  final List<Movie> movies;
  final ValueChanged<Movie> onOpen;
  final String featureLabel;
  const _Featured({super.key,required this.movies,required this.onOpen,this.featureLabel=''});
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
              if(widget.featureLabel.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:5),child:Text(widget.featureLabel,style:const TextStyle(color:CinemaColors.accent,fontSize:10,letterSpacing:1.2,fontWeight:FontWeight.w700))),
              Text(m.title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:27,fontWeight:FontWeight.w800,height:1.1)),
              const SizedBox(height:6),Text(m.metadata,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:CinemaColors.muted,fontSize:11)),
              if(m.description.isNotEmpty&&!landscape)Padding(padding:const EdgeInsets.only(top:5),child:Text(m.description,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11))),
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
