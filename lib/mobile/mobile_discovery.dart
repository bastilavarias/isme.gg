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
