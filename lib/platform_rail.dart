import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'engine.dart';
import 'platform_logos.dart';

class PlatformBrand {
  final String key,name;
  final Color color;
  final List<String> aliases;
  const PlatformBrand(this.key,this.name,this.color,this.aliases);
  static const all=PlatformBrand('all','All',Color(0xFF292929),[]);
  static const brands=[
    all,
    PlatformBrand('netflix','Netflix',Color(0xFF191919),['netflix','netflix standard with ads','netflix basic with ads']),
    PlatformBrand('disney','Disney+',Color(0xFFEDF5FF),['disney plus','disney+']),
    PlatformBrand('prime','Prime Video',Color(0xFFE8F5FC),['amazon prime video','amazon prime video with ads','prime video']),
    PlatformBrand('max','HBO Max',Color(0xFF241F38),['max','hbo max','max with ads','hbo max with ads']),
    PlatformBrand('apple','Apple TV',Color(0xFF191919),['apple tv','apple tv plus','apple tv+']),
    PlatformBrand('crunchyroll','Crunchyroll',Color(0xFFFFF4E8),['crunchyroll']),
    PlatformBrand('hulu','Hulu',Color(0xFF10291E),['hulu']),
    PlatformBrand('paramount','Paramount+',Color(0xFF163B87),['paramount plus','paramount+','paramount plus essential','paramount plus premium','paramount plus with showtime']),
    PlatformBrand('peacock','Peacock',Color(0xFF242424),['peacock','peacock premium','peacock premium plus']),
    PlatformBrand('iwant','iWant',Color(0xFF292340),['iwant','iwanttfc','iwant tfc']),
    PlatformBrand('viu','Viu',Color(0xFF30291A),['viu','viu premium']),
    PlatformBrand('iqiyi','iQIYI',Color(0xFF142D21),['iqiyi']),
  ];
  List<WatchProvider> matches(List<WatchProvider> providers)=>providers.where((p)=>aliases.contains(p.name.trim().toLowerCase())).toList();
  String logo(List<WatchProvider> providers)=>matches(providers).where((p)=>p.logo.startsWith('https://image.tmdb.org/')).firstOrNull?.logo??'';
}

class PlatformRail extends StatefulWidget {
  final List<WatchProvider> providers;
  final PlatformBrand selected;
  final ValueChanged<PlatformBrand> onSelected;
  final VoidCallback onUp,onDown;
  final bool tv;
  const PlatformRail({super.key,required this.providers,required this.selected,required this.onSelected,required this.onUp,required this.onDown,required this.tv});
  @override State<PlatformRail> createState()=>PlatformRailState();
}
class PlatformRailState extends State<PlatformRail>{
  final nodes=List.generate(PlatformBrand.brands.length,(i)=>FocusNode(debugLabel:'Platform $i'));
  final scroll=ScrollController();
  int cursor=0;
  void focusRemembered(){
    final i=PlatformBrand.brands.indexWhere((b)=>b.key==widget.selected.key);
    focusAt(i<0?cursor:i);
  }
  void focusAt(int i){
    if(!mounted)return;
    cursor=i.clamp(0,nodes.length-1).toInt();
    nodes[cursor].requestFocus();
    final ctx=nodes[cursor].context;
    if(ctx!=null)Scrollable.ensureVisible(ctx,duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:220),alignmentPolicy:ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
  }
  KeyEventResult keys(FocusNode node,KeyEvent event){
    if(!widget.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowLeft){focusAt(cursor-1);return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowRight){focusAt(cursor+1);return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){widget.onUp();return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowDown){widget.onDown();return KeyEventResult.handled;}
    return KeyEventResult.ignored;
  }
  @override void dispose(){for(final node in nodes)node.dispose();scroll.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final tv=widget.tv;
    return Focus(canRequestFocus:false,onKeyEvent:keys,child:Padding(padding:const EdgeInsets.only(bottom:22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Padding(padding:EdgeInsets.symmetric(horizontal:tv?40:16),child:const Text('Explore platforms',style:TextStyle(fontSize:21,fontWeight:FontWeight.w700))),
      const SizedBox(height:10),
      SingleChildScrollView(controller:scroll,scrollDirection:Axis.horizontal,padding:EdgeInsets.symmetric(horizontal:tv?40:16),child:Row(children:[
        for(var i=0;i<PlatformBrand.brands.length;i++) Padding(padding:const EdgeInsets.only(right:10),child: SizedBox(width:tv?146:118,height:tv?88:74,
          child:RemoteTile(focusNode:nodes[i],label:PlatformBrand.brands[i].name,animateFocus:true,
            onFocused:(){cursor=i;},onPressed:()=>widget.onSelected(PlatformBrand.brands[i]),child:_BrandCard(brand:PlatformBrand.brands[i],logo:PlatformBrand.brands[i].logo(widget.providers),selected:widget.selected.key==PlatformBrand.brands[i].key)))),
      ])),
    ])));
  }
}
class _BrandCard extends StatelessWidget{
  final PlatformBrand brand;final String logo;final bool selected;
  const _BrandCard({required this.brand,required this.logo,required this.selected});
  static const _wordmarks={'netflix','disney','prime','crunchyroll','hulu','viu'};
  @override Widget build(BuildContext context){
    final bytes=bundledPlatformLogo(brand.key);
    final wide=_wordmarks.contains(brand.key);
    final light=brand.key=='disney'||brand.key=='prime'||brand.key=='crunchyroll';
    final label=Text(brand.name,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,
      style:TextStyle(fontWeight:FontWeight.w700,fontSize:13,color:light?const Color(0xFF172234):CinemaColors.ink));
    Widget content;
    if(wide&&bytes!=null){
      content=Padding(padding:const EdgeInsets.symmetric(horizontal:18,vertical:16),
        child:Image.memory(bytes,fit:BoxFit.contain,excludeFromSemantics:true,
          errorBuilder:(_,__,___)=>Center(child:label)));
    }else{
      content=Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),
        child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          if(brand.key=='all')const Padding(padding:EdgeInsets.only(right:6),child:Icon(Icons.grid_view_rounded,size:20)),
          if(bytes!=null||logo.isNotEmpty)Padding(padding:const EdgeInsets.only(right:6),child:ClipRRect(
            borderRadius:BorderRadius.circular(7),child:bytes!=null
              ?Image.memory(bytes,width:36,height:36,fit:BoxFit.contain,excludeFromSemantics:true,errorBuilder:(_,__,___)=>const SizedBox.shrink())
              :Image.network(logo,width:36,height:36,fit:BoxFit.contain,cacheWidth:96,excludeFromSemantics:true,errorBuilder:(_,__,___)=>const SizedBox.shrink()))),
          Flexible(child:label),
        ]));
    }
    return AnimatedContainer(duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:200),
    decoration:BoxDecoration(color:brand.color,borderRadius:BorderRadius.circular(6),border:Border.all(color:selected?CinemaColors.accent:Colors.transparent,width:1.5)),
    child:Stack(fit:StackFit.expand,children:[
      Center(child:content),
      if(selected)const Positioned(right:5,top:4,child:Icon(Icons.check_circle,size:13,color:CinemaColors.accent)),
    ]));
  }
}
