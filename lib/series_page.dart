import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'engine.dart';
import 'player.dart';

/// Cinematic season tabs and landscape episode rail. Both series and anime use
/// the provider's season/episode numbers verbatim, including season zero.
class SeriesPage extends StatefulWidget {
  final Movie show;
  final NativeEngine engine;
  final History history;
  const SeriesPage({super.key,required this.show,required this.engine,required this.history});
  @override State<SeriesPage> createState()=>_SeriesPageState();
}
class _SeriesPageState extends State<SeriesPage> {
  final _seasonScroll=ScrollController(), _episodeScroll=ScrollController();
  final _back=FocusNode(debugLabel:'Back');
  final _seasonScope=FocusScopeNode(debugLabel:'Seasons'),_episodeScope=FocusScopeNode(debugLabel:'Episodes');
  List<Season> _seasons=[];
  List<Episode> _episodes=[];
  int? _season;
  Episode? _highlight;
  bool _loading=true;
  String? _error;
  int _generation=0;
  Duration get _motion=>MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:260);
  @override void initState(){super.initState();_loadSeasons();}
  Future<void> _loadSeasons() async {
    setState((){_loading=true;_error=null;});
    final run=++_generation;
    try{
      final list=await widget.engine.seasons(widget.show);
      if(!mounted||run!=_generation)return;
      setState((){_seasons=list;});
      if(list.isEmpty){setState((){_loading=false;_error='No season information available.';});return;}
      await _chooseSeason(list.firstWhere((s)=>s.number>0,orElse:()=>list.first).number);
    }catch(_){
      if(mounted&&run==_generation)setState((){_loading=false;_error='Season information unavailable. Connect TMDB or try again.';});
    }
  }
  Future<void> _chooseSeason(int number,{bool focusEpisodes=false}) async {
    final run=++_generation;
    setState((){_season=number;_episodes=[];_highlight=null;_loading=true;_error=null;});
    if(_episodeScroll.hasClients)_episodeScroll.jumpTo(0);
    try{
      final list=await widget.engine.episodes(widget.show,number);
      if(!mounted||run!=_generation)return;
      setState((){_episodes=list;_highlight=list.firstOrNull;_loading=false;});
      if(focusEpisodes&&list.isNotEmpty)WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted&&run==_generation)_episodeScope.requestFocus();
      });
    }catch(_){
      if(mounted&&run==_generation)setState((){_loading=false;_error='Episodes unavailable. Connect TMDB or try again.';});
    }
  }
  KeyEventResult _seasonKeys(FocusNode node,KeyEvent event){
    if(!widget.engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){_back.requestFocus();return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowDown){if(_episodes.isNotEmpty)_episodeScope.requestFocus();return KeyEventResult.handled;}
    return KeyEventResult.ignored;
  }
  KeyEventResult _episodeKeys(FocusNode node,KeyEvent event){
    if(!widget.engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){_seasonScope.requestFocus();return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowDown)return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }
  Future<void> _openEpisode(Episode ep) async {
    final season=_season;
    if(season==null)return;
    final controller=TextEditingController();
    final source=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('S$season E${ep.number} · ${ep.title}'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(ep.description.isNotEmpty)Text(ep.description),
        const SizedBox(height:12),
        const Text('Episode metadata does not include a video. Open a media source you are authorized to use.'),
        const SizedBox(height:12),
        TextField(controller:controller,decoration:const InputDecoration(labelText:'Permitted magnet URI')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('Open source'))]));
    controller.dispose();
    if(!mounted||source==null||source.isEmpty)return;
    if(!RegExp(r'^magnet:\?xt=urn:btih:[a-fA-F0-9]{40}(?:&.*)?$').hasMatch(source)){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid hexadecimal BTIH magnet.')));return;
    }
    final media=Movie(id:'${widget.show.id}:s$season:e${ep.number}',title:'${widget.show.title} · S$season E${ep.number}',
      type:widget.show.type,poster:widget.show.poster,backdrop:ep.thumbnail,description:ep.description);
    await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>CinemaPlayer(movie:media,engine:widget.engine,history:widget.history,magnet:source)));
  }
  @override void dispose(){_generation++;_seasonScroll.dispose();_episodeScroll.dispose();_back.dispose();_seasonScope.dispose();_episodeScope.dispose();super.dispose();}
  Widget _tabs()=>Focus(canRequestFocus:false,onKeyEvent:_seasonKeys,
    child:FocusScope(node:_seasonScope,child:SizedBox(height:48,child:ListView.separated(
      controller:_seasonScroll,scrollDirection:Axis.horizontal,itemCount:_seasons.length,
      separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(context,i){
        final s=_seasons[i];final active=s.number==_season;
        return RemoteTile(label:s.name,autofocus:widget.engine.tv&&active,
          onPressed:()=>_chooseSeason(s.number,focusEpisodes:widget.engine.tv),
          child:Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Text(s.name,style:TextStyle(color:active?CinemaColors.ink:CinemaColors.muted,fontWeight:active?FontWeight.w600:FontWeight.w400)),
            const SizedBox(height:4),AnimatedContainer(duration:_motion,width:active?32:0,height:2,color:CinemaColors.accent),
          ])));
      }))));
  Widget _rail(bool tv)=>Focus(canRequestFocus:false,onKeyEvent:_episodeKeys,
    child:FocusScope(node:_episodeScope,child:SizedBox(height:tv?176:154,child:ListView.builder(
      key:ValueKey(_season),controller:_episodeScroll,scrollDirection:Axis.horizontal,itemCount:_episodes.length,
      itemBuilder:(context,i){
        final ep=_episodes[i];final active=_highlight?.number==ep.number;
        return Padding(padding:const EdgeInsets.only(right:10),child:AnimatedContainer(
          duration:_motion,curve:Curves.easeOutCubic,width:tv?(active?252:218):194,
          child:RemoteTile(key:ValueKey('episode-${ep.number}'),label:'Episode ${ep.number}: ${ep.title}',animateFocus:true,
            onFocused:(){if(mounted&&_highlight?.number!=ep.number)setState(()=>_highlight=ep);},
            onPressed:()=>_openEpisode(ep),
            child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Expanded(child:Stack(fit:StackFit.expand,children:[
                CinemaArt(ep.thumbnail.isEmpty?widget.show.art:ep.thumbnail,cacheWidth:480),
                if(active)const Align(alignment:Alignment.center,child:Icon(Icons.play_circle_outline,size:36)),
              ])),
              Padding(padding:const EdgeInsets.fromLTRB(6,5,6,1),child:Text('EPISODE ${ep.number}',style:const TextStyle(color:CinemaColors.accent,fontSize:10,fontWeight:FontWeight.w600))),
              Padding(padding:const EdgeInsets.fromLTRB(6,0,6,5),child:Text(ep.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13))),
            ]))));
      }))));
  @override Widget build(BuildContext context){
    final show=widget.show,tv=widget.engine.tv,ep=_highlight;
    final art=ep?.thumbnail.isNotEmpty==true?ep!.thumbnail:show.art;
    final info=[if(_season!=null&&ep!=null)'S$_season · E${ep.number}',if(ep!=null&&ep.runtime>0)'${ep.runtime} min',if(ep!=null&&ep.airDate.isNotEmpty)ep.airDate.split('T').first].join('  ·  ');
    return Scaffold(body:SafeArea(child:Stack(fit:StackFit.expand,children:[
      Align(alignment:Alignment.topRight,child:SizedBox(width:MediaQuery.sizeOf(context).width*(tv ? .85 : 1),height:MediaQuery.sizeOf(context).height*.78,
        child:AnimatedSwitcher(duration:_motion,layoutBuilder:(current,previous)=>Stack(fit:StackFit.expand,children:[...previous,if(current!=null)current]),
          child:CinemaArt(art,key:ValueKey(art),cacheWidth:1280)))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[CinemaColors.canvas,Color(0xD911110F),Color(0x4411110F)],stops:[0,.35,1]))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,CinemaColors.canvas],stops:[.18,.91]))),
      Padding(padding:EdgeInsets.symmetric(horizontal:tv?40:18,vertical:12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Align(alignment:Alignment.topLeft,child:IconButton(focusNode:_back,onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.arrow_back))),
          Expanded(child:Align(alignment:Alignment.bottomLeft,child:SingleChildScrollView(child:ConstrainedBox(
            constraints:BoxConstraints(maxWidth:tv?580:double.infinity),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
              Text(show.title,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?36:28,fontWeight:FontWeight.w800,height:1.1)),
              const SizedBox(height:6),Text(show.metadata,style:const TextStyle(color:CinemaColors.muted,fontSize:12)),
              const SizedBox(height:14),
              AnimatedSwitcher(duration:_motion,layoutBuilder:(current,previous)=>Stack(alignment:Alignment.topLeft,children:[...previous,if(current!=null)current]),
                child:Column(key:ValueKey('$_season:${ep?.number}'),crossAxisAlignment:CrossAxisAlignment.start,children:[
                  if(ep!=null)Text(ep.title,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?21:17,fontWeight:FontWeight.w600)),
                  if(info.isNotEmpty)Text(info,style:const TextStyle(color:CinemaColors.accent,fontSize:12)),
                  const SizedBox(height:4),
                  Text(ep?.description.isNotEmpty==true?ep!.description:show.description,maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13,height:1.4)),
                ])),
            ]))))),
          const SizedBox(height:12),
          if(_seasons.isNotEmpty)_tabs(),
          const SizedBox(height:8),
          if(_loading)const Padding(padding:EdgeInsets.symmetric(vertical:24),child:LinearProgressIndicator())
          else if(_error!=null)Row(children:[Expanded(child:Text(_error!,style:const TextStyle(color:CinemaColors.muted))),TextButton(onPressed:()=>_season==null?_loadSeasons():_chooseSeason(_season!),child:const Text('Retry'))])
          else if(_episodes.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('No episodes listed.'))
          else _rail(tv),
          const SizedBox(height:5),
          const Text('Metadata from TMDB / Cinemeta',style:TextStyle(color:CinemaColors.muted,fontSize:10)),
        ])),
    ])));
  }
}
