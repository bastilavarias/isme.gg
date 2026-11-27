import 'package:flutter/material.dart';
import '../back_navigation.dart';
import '../category_catalog.dart';
import '../design.dart';
import '../engine.dart';
import '../platform_rail.dart';
import 'mobile_widgets.dart';

class DiscoveryTile {
  final String name;
  final IconData icon;
  final Color color;
  final List<String> collections;
  const DiscoveryTile(this.name,this.icon,this.color,this.collections);
}

// Use only catalog keys with implemented metadata queries.
final mobileCategories=[
  for(final item in const [
    ('Movies',Icons.movie_outlined,Color(0xFF45302A)),
    ('TV Series',Icons.tv_outlined,Color(0xFF293B48)),
    ('Anime',Icons.animation,Color(0xFF48334B)),
    ('Pinoy',Icons.public,Color(0xFF395044)),
  ]) DiscoveryTile(item.$1,item.$2,item.$3,categorySections(item.$1,{}).keys.toList()),
  const DiscoveryTile('Korean',Icons.favorite_border,Color(0xFF50343B),['korean_home','page_series_korean']),
];
const mobileGenres=[
  DiscoveryTile('Action & Adventure',Icons.bolt,Color(0xFF4C3026),['page_movies_action','page_anime_action','page_pinoy_action']),
  DiscoveryTile('Comedy',Icons.sentiment_satisfied_alt,Color(0xFF625026),['page_movies_comedy','page_series_comedy','page_pinoy_comedy']),
  DiscoveryTile('Horror & Thriller',Icons.visibility_outlined,Color(0xFF49262C),['page_movies_horror','page_pinoy_horror']),
  DiscoveryTile('Romance',Icons.favorite_border,Color(0xFF603B4E),['page_movies_romance','page_pinoy_romance']),
  DiscoveryTile('Sci-Fi',Icons.rocket_launch_outlined,Color(0xFF293D58),['page_movies_scifi']),
  DiscoveryTile('Crime & Mystery',Icons.search,Color(0xFF353C3E),['page_series_crime']),
  DiscoveryTile('Drama',Icons.theater_comedy_outlined,Color(0xFF403650),['page_series_drama']),
];

/// Artwork comes from the matching home catalog, never a generic unrelated title.
const discoveryArtworkKeys={'Movies':'weekly_movies','TV Series':'weekly_tv',
  'Anime':'anime','Pinoy':'pinoy_home','Korean':'korean_home'};

/// Prefer actual landscape artwork, never stretch a portrait poster.
String? discoveryBackdrop(Iterable<Movie> movies){
  for(final movie in movies){
    if(movie.backdrop.startsWith('https://')&&movie.backdrop!=movie.poster)return movie.backdrop;
  }
  return null;
}

/// Full-width cinematic category banners using matching catalog backdrops.
class DiscoveryCategoryList extends StatelessWidget {
  final List<DiscoveryTile> tiles;
  final Map<String,String> backdrops;
  final ValueChanged<DiscoveryTile> onSelected;
  const DiscoveryCategoryList({super.key,required this.tiles,required this.backdrops,required this.onSelected});
  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    for(var i=0;i<tiles.length;i++)...[
      if(i>0)const SizedBox(height:12),
      _CategoryCard(tile:tiles[i],backdrop:backdrops[tiles[i].name],onTap:()=>onSelected(tiles[i])),
    ],
  ]);
}
class _CategoryCard extends StatelessWidget {
  final DiscoveryTile tile;
  final String? backdrop;
  final VoidCallback onTap;
  const _CategoryCard({required this.tile,required this.backdrop,required this.onTap});
  @override Widget build(BuildContext context)=>SizedBox(height:116,child:Material(
    color:tile.color,borderRadius:BorderRadius.circular(12),clipBehavior:Clip.antiAlias,
    child:Stack(fit:StackFit.expand,children:[
      if(backdrop!=null)ExcludeSemantics(child:Image.network(backdrop!,fit:BoxFit.cover,
        alignment:Alignment.centerRight,cacheWidth:960,
        errorBuilder:(_,__,___)=>const SizedBox.shrink()))
      else Positioned(right:32,top:0,bottom:0,child:Icon(tile.icon,size:64,color:Colors.white24)),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
        colors:[Color(0xF2161311),Color(0xB8161311),Color(0x35161311)],
        stops:[0,.48,1]))),
      Material(color:Colors.transparent,child:InkWell(
        key:ValueKey('mobile-discover-${tile.name}'),onTap:onTap,
        child:Padding(padding:const EdgeInsets.symmetric(horizontal:18),child:Row(children:[
          Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(tile.name,maxLines:2,overflow:TextOverflow.ellipsis,
              style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w700)),
            const SizedBox(height:4),
            const Text('Explore collection',style:TextStyle(color:Colors.white70,fontSize:12)),
          ])),
          const SizedBox(width:12),
          const Icon(Icons.chevron_right,color:Colors.white,size:24),
        ])))),
    ])));
}

class DiscoveryGrid extends StatelessWidget {
  final List<DiscoveryTile> tiles;
  final ValueChanged<DiscoveryTile> onSelected;
  const DiscoveryGrid({super.key,required this.tiles,required this.onSelected});
  @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,box){
    final columns=box.maxWidth>=600?3:2;
    final width=(box.maxWidth-(columns-1)*10)/columns;
    return Wrap(spacing:10,runSpacing:10,children:[
      for(final tile in tiles)SizedBox(width:width,height:88,child:Material(
        color:tile.color,borderRadius:BorderRadius.circular(12),clipBehavior:Clip.antiAlias,
        child:InkWell(key:ValueKey('mobile-discover-${tile.name}'),onTap:()=>onSelected(tile),
          child:Padding(padding:const EdgeInsets.all(12),child:Stack(children:[
            Align(alignment:Alignment.topRight,child:Icon(tile.icon,size:28,color:Colors.white54)),
            Align(alignment:Alignment.bottomLeft,child:Text(tile.name,maxLines:2,
              style:const TextStyle(color:Colors.white,fontSize:15,fontWeight:FontWeight.w700))),
          ]))))),
    ]);
  });
}

class MobileDiscoveryCatalog extends StatefulWidget {
  final String title;
  final NativeEngine engine;
  final List<String> collections;
  final PlatformBrand? brand;
  final List<WatchProvider> providers;
  final void Function(BuildContext,Movie) onOpen;
  const MobileDiscoveryCatalog({super.key,required this.title,required this.engine,
    this.collections=const [],this.brand,this.providers=const [],required this.onOpen});
  @override State<MobileDiscoveryCatalog> createState()=>_MobileDiscoveryCatalogState();
}
class _MobileDiscoveryCatalogState extends State<MobileDiscoveryCatalog>{
  final movies=<Movie>[];
  bool loading=true,failed=false;
  int revision=0;
  @override void initState(){super.initState();load();}
  @override void dispose(){revision++;super.dispose();}
  Future<void> load() async {
    final n=++revision;
    setState((){loading=true;failed=false;movies.clear();});
    final brand=widget.brand;
    final jobs=<Future<CatalogSnapshot> Function()>[
      if(brand==null)
        for(final key in widget.collections)()=>widget.engine.catalogSnapshot(key)
      else
        for(final kind in ['movie','tv'])
          if(brand.matches(widget.providers).any((p)=>kind=='movie'?p.movie:p.tv))
            for(final row in ['popular','recent','rated'])
              ()=>widget.engine.platformCatalog(brand.matches(widget.providers)
                .where((p)=>kind=='movie'?p.movie:p.tv).map((p)=>p.id).toList(),kind,row),
    ];
    final seen=<String>{};
    for(var i=0;i<jobs.length;i+=2){
      if(!mounted||n!=revision)return;
      await Future.wait(jobs.skip(i).take(2).map((job)async{
        try{
          final data=await job();
          if(mounted&&n==revision)setState(()=>movies.addAll(data.movies.where((m)=>seen.add(m.id))));
        }catch(_){if(mounted&&n==revision)setState(()=>failed=true);}
      }));
    }
    if(mounted&&n==revision)setState(()=>loading=false);
  }
  @override Widget build(BuildContext context)=>BackNavigationScope(child:Scaffold(
    appBar:AppBar(title:Text(widget.title),leading:BackButton(onPressed:()=>Navigator.of(context).maybePop())),
    body:Column(children:[
      if(loading)const LinearProgressIndicator(minHeight:2),
      Expanded(child:movies.isEmpty?MobileEmpty(loading?'Loading…':failed?'Catalog unavailable':'No titles available',
        loading?'Finding titles…':failed?'Please try again.':'Try another category.',retry:loading?null:load):
        MobileGrid(movies:movies,engine:widget.engine,onOpen:(movie)=>widget.onOpen(context,movie))),
    ]),
  ));
}
