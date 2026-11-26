import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'engine.dart';
import 'player.dart';
import 'next_episode.dart';

/// Ignore provider fallback names that merely repeat the episode number.
String distinctEpisodeTitle(Episode ep){
  final title=ep.title.trim();
  final normalized=title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'),'');
  if(title.isEmpty||normalized=='episode${ep.number}'||normalized=='ep${ep.number}'||normalized=='e${ep.number}'||normalized=='${ep.number}')return '';
  return title;
}
String episodeDateLabel(BuildContext context,String value){
  final date=DateTime.tryParse(value.trim());
  if(date==null)return '';
  return MaterialLocalizations.of(context).formatShortDate(DateTime(date.year,date.month,date.day));
}

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
  int? _focusedEpisode;
  static const _narrow=100.0,_wide=252.0,_gap=10.0;
  final _episodeNodes=<String,FocusNode>{};
  int _focusRevision=0;
  String _episodeKey(Episode ep)=>'$_season:${ep.number}';
  FocusNode _episodeNode(Episode ep)=>_episodeNodes.putIfAbsent(_episodeKey(ep),()=>FocusNode(debugLabel:'Episode ${ep.number}'));
  void _revealEpisode(int index,int revision){
    if(!mounted||revision!=_focusRevision||!_episodeScroll.hasClients)return;
    final pos=_episodeScroll.position;
    if(!pos.hasContentDimensions)return;
    final left=index*(_narrow+_gap),right=left+_wide;
    var target=pos.pixels;
    if(left<target)target=left;
    else if(right>target+pos.viewportDimension)target=right-pos.viewportDimension;
    target=target.clamp(pos.minScrollExtent,pos.maxScrollExtent).toDouble();
    if((target-pos.pixels).abs()<1)return;
    if(_motion==Duration.zero)pos.jumpTo(target);
    else pos.animateTo(target,duration:_motion,curve:Curves.easeOutCubic);
  }
  void _focusEpisode(int index){
    if(index<0||index>=_episodes.length)return;
    final node=_episodeNode(_episodes[index]);
    if(node.context!=null){node.requestFocus();return;}
    if(!_episodeScroll.hasClients)return;
    final rev=++_focusRevision;
    final pos=_episodeScroll.position;
    final offset=(index*(_narrow+_gap)).clamp(pos.minScrollExtent,pos.maxScrollExtent).toDouble();
    if(_motion==Duration.zero)pos.jumpTo(offset);
    else pos.animateTo(offset,duration:_motion,curve:Curves.easeOutCubic);
    Future<void>.delayed(_motion,(){
      if(!mounted||rev!=_focusRevision)return;
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&rev==_focusRevision&&node.context!=null)node.requestFocus();});
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }
  void _episodeFocus(Episode ep,int index,bool focused){
    if(!mounted||!_episodes.contains(ep))return;
    if(!focused){if(_focusedEpisode==ep.number){_focusRevision++;setState(()=>_focusedEpisode=null);}return;}
    final rev=++_focusRevision;
    setState((){_focusedEpisode=ep.number;_highlight=ep;});
    WidgetsBinding.instance.addPostFrameCallback((_)=>_revealEpisode(index,rev));
  }
  bool _loading=true, _openingEpisode=false;
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
    _focusRevision++;
    final oldNodes=_episodeNodes.values.toList();_episodeNodes.clear();
    setState((){_season=number;_episodes=[];_highlight=null;_focusedEpisode=null;_loading=true;_error=null;});
    WidgetsBinding.instance.addPostFrameCallback((_){for(final node in oldNodes)node.dispose();});
    if(_episodeScroll.hasClients)_episodeScroll.jumpTo(0);
    try{
      final list=await widget.engine.episodes(widget.show,number);
      if(!mounted||run!=_generation)return;
      setState((){_episodes=list;_highlight=list.firstOrNull;_loading=false;});
      if(focusEpisodes&&list.isNotEmpty)WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted&&run==_generation)_focusEpisode(0);
      });
    }catch(_){
      if(mounted&&run==_generation)setState((){_loading=false;_error='Episodes unavailable. Connect TMDB or try again.';});
    }
  }
  KeyEventResult _seasonKeys(FocusNode node,KeyEvent event){
    if(!widget.engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){_back.requestFocus();return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowDown){if(_episodes.isNotEmpty){final index=_episodes.indexWhere((e)=>e.number==_highlight?.number);_focusEpisode(index<0?0:index);}return KeyEventResult.handled;}
    return KeyEventResult.ignored;
  }
  KeyEventResult _episodeKeys(FocusNode node,KeyEvent event){
    if(!widget.engine.tv||event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){_focusRevision++;_seasonScope.requestFocus();return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.arrowLeft||event.logicalKey==LogicalKeyboardKey.arrowRight){
      final i=_episodes.indexWhere((e)=>e.number==_highlight?.number);
      _focusEpisode(i+(event.logicalKey==LogicalKeyboardKey.arrowRight?1:-1));return KeyEventResult.handled;
    }
    if(event.logicalKey==LogicalKeyboardKey.arrowDown)return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }
  Future<void> _openEpisode(Episode ep) async {
    final season=_season;
    if(season==null)return;
    if(_openingEpisode)return;
    _openingEpisode=true;
    final media=episodeMovie(widget.show,season,ep);
    try{
      await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>CinemaPlayer(movie:media,engine:widget.engine,history:widget.history)));
    }finally{
      if(mounted)setState(()=>_openingEpisode=false);
    }
  }
  @override void dispose(){_generation++;_seasonScroll.dispose();_episodeScroll.dispose();_back.dispose();_seasonScope.dispose();_episodeScope.dispose();_focusRevision++;for(final node in _episodeNodes.values)node.dispose();super.dispose();}
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
      cacheExtent:_wide+_narrow,
      itemBuilder:(context,i){
        final ep=_episodes[i];final active=tv&&_focusedEpisode==ep.number;
        final title=distinctEpisodeTitle(ep);
        final art=ep.thumbnail.isEmpty?widget.show.art:ep.thumbnail;
        return Padding(key:ValueKey(_episodeKey(ep)),padding:const EdgeInsets.only(right:_gap),child:AnimatedContainer(
          key:ValueKey('episode-size-${ep.number}'),
          duration:_motion,curve:Curves.easeOutCubic,width:tv?(active?_wide:_narrow):194,
          onEnd:(){if(active&&_focusedEpisode==ep.number)_revealEpisode(i,_focusRevision);},
          child:RemoteTile(key:ValueKey('episode-${ep.number}'),label:title.isEmpty?'Episode ${ep.number}':'Episode ${ep.number}: $title',animateFocus:true,
            focusNode:tv?_episodeNode(ep):null,revealOnFocus:!tv,
            onFocusChanged:tv?(focused)=>_episodeFocus(ep,i,focused):null,
            onPressed:()=>_openEpisode(ep),
            child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Expanded(child:Stack(fit:StackFit.expand,children:[
                CinemaArt(art,cacheWidth:480),
                if(active)const Align(alignment:Alignment.center,child:Icon(Icons.play_circle_outline,size:36)),
              ])),
              SizedBox(height:34,child:Padding(padding:const EdgeInsets.fromLTRB(6,3,6,3),child:Column(
                mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('EPISODE ${ep.number}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:CinemaColors.accent,fontSize:10,fontWeight:FontWeight.w600)),
                  if(title.isNotEmpty)Expanded(child:Text(title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:12))),
                ]))),
            ]))));
      }))));
  @override Widget build(BuildContext context){
    final show=widget.show,tv=widget.engine.tv,ep=_highlight;
    final art=ep?.thumbnail.isNotEmpty==true?ep!.thumbnail:show.art;
    final date=ep==null?'':episodeDateLabel(context,ep.airDate);
    final info=[if(_season!=null&&ep!=null)'S$_season · E${ep.number}',if(ep!=null&&ep.runtime>0)'${ep.runtime} min',if(date.isNotEmpty)date].join('  ·  ');
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
                  if(ep!=null)Text(distinctEpisodeTitle(ep).isEmpty?'Episode ${ep.number}':distinctEpisodeTitle(ep),maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?21:17,fontWeight:FontWeight.w600)),
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

        ])),
    ])));
  }
}
