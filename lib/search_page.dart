import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'engine.dart';
import 'platform_pill.dart';

/// The built-in TV keyboard is independent of Android's input method.
class CinemaSearchPage extends StatefulWidget {
  final NativeEngine engine;
  final TextEditingController controller;
  final List<Movie> movies;
  final bool busy;
  final String? error;
  final ValueChanged<String> onQuery;
  final ValueChanged<Movie> onOpen;
  final VoidCallback onNav;
  const CinemaSearchPage({super.key,required this.engine,required this.controller,
    required this.movies,required this.busy,required this.error,
    required this.onQuery,required this.onOpen,required this.onNav});
  @override CinemaSearchPageState createState()=>CinemaSearchPageState();
}

class CinemaSearchPageState extends State<CinemaSearchPage> {
  static const letters='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static const columns=6, keyCount=40;
  final keys=List.generate(keyCount,(i)=>FocusNode(debugLabel:'Search key $i'));
  final nativeKey=FocusNode(debugLabel:'TV keyboard');
  final resultNodes=<String,FocusNode>{};
  final scroll=ScrollController();
  int lastKey=0, lastResult=0, resultColumns=3;
  double resultStride=180;
  bool nativeOpen=false;

  void focusKeyboard(){if(mounted)keys[lastKey].requestFocus();}
  void change(String value){
    widget.controller.value=TextEditingValue(text:value,selection:TextSelection.collapsed(offset:value.length));
    widget.onQuery(value);
  }
  void append(String value){
    if(widget.controller.text.length+value.length<=120)change(widget.controller.text+value);
  }
  void erase(){
    final value=widget.controller.text;
    if(value.isNotEmpty)change(String.fromCharCodes(value.runes.take(value.runes.length-1)));
  }
  void activate(int i){
    if(i<36)append(letters[i]);
    else if(i==36)append(' ');
    else if(i==37)erase();
    else if(i==38)change('');
    else focusResult(lastResult);
  }
  Future<void> openNative() async {
    if(nativeOpen)return;
    nativeOpen=true;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Search with TV keyboard'),
      content:TextField(controller:widget.controller,autofocus:true,
        textInputAction:TextInputAction.search,maxLength:120,
        decoration:const InputDecoration(hintText:'Find a movie',counterText:''),
        onChanged:widget.onQuery,onSubmitted:(_)=>Navigator.of(ctx).pop()),
      actions:[TextButton(onPressed:()=>Navigator.of(ctx).pop(),child:const Text('Done'))],
    ));
    if(!mounted)return;
    nativeOpen=false;
    nativeKey.requestFocus();
  }
  FocusNode resultNode(Movie m)=>resultNodes.putIfAbsent(m.id,()=>FocusNode(debugLabel:'Search result: ${m.title}'));
  void focusResult(int index){
    if(widget.movies.isEmpty)return;
    final i=index.clamp(0,widget.movies.length-1).toInt();
    final movie=widget.movies[i],node=resultNode(movie);
    lastResult=i;
    if(node.context!=null){node.requestFocus();return;}
    if(scroll.hasClients){
      final pos=scroll.position;
      final target=((i~/resultColumns)*resultStride).clamp(0.0,pos.maxScrollExtent).toDouble();
      scroll.jumpTo(target);
    }
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&widget.movies.any((m)=>m.id==movie.id)&&node.context!=null)node.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
  bool pressed(KeyEvent e)=>e is KeyDownEvent||e is KeyRepeatEvent;
  KeyEventResult keyboardEvent(FocusNode _,KeyEvent e){
    if(!pressed(e)||nativeOpen)return KeyEventResult.ignored;
    final k=e.logicalKey;
    final i=keys.indexWhere((n)=>n.hasFocus);
    if(i<0){
      if(!nativeKey.hasFocus)return KeyEventResult.ignored;
      if(k==LogicalKeyboardKey.arrowUp)widget.onNav();
      else if(k==LogicalKeyboardKey.arrowDown)focusKeyboard();
      else if(k==LogicalKeyboardKey.arrowRight)focusResult(lastResult);
      else if(k==LogicalKeyboardKey.arrowLeft)focusKeyboard();
      else return KeyEventResult.ignored;
      return KeyEventResult.handled;
    }
    final row=i~/columns,col=i%columns;
    if(k==LogicalKeyboardKey.arrowUp){
      if(row==0)nativeKey.requestFocus();
      else if(i>=36)keys[30+((i-36)*6~/4)].requestFocus();
      else keys[i-columns].requestFocus();
    }else if(k==LogicalKeyboardKey.arrowDown){
      if(i<30)keys[i+columns].requestFocus();
      else if(i<36)keys[36+(col*4~/6)].requestFocus();
    }else if(k==LogicalKeyboardKey.arrowRight){
      if((i<36&&col==5)||i==39)focusResult(lastResult);
      else keys[i+1].requestFocus();
    }else if(k==LogicalKeyboardKey.arrowLeft){
      if((i<36&&col>0)||i>36)keys[i-1].requestFocus();
    }else return KeyEventResult.ignored;
    return KeyEventResult.handled;
  }
  KeyEventResult resultEvent(FocusNode _,KeyEvent e){
    if(!pressed(e))return KeyEventResult.ignored;
    final i=widget.movies.indexWhere((m)=>resultNodes[m.id]?.hasFocus==true);
    if(i<0)return KeyEventResult.ignored;
    final k=e.logicalKey;
    if(k==LogicalKeyboardKey.arrowLeft){
      if(i%resultColumns==0)focusKeyboard();else focusResult(i-1);
    }else if(k==LogicalKeyboardKey.arrowRight){
      if(i%resultColumns<resultColumns-1&&i+1<widget.movies.length)focusResult(i+1);
    }else if(k==LogicalKeyboardKey.arrowUp){
      if(i<resultColumns)widget.onNav();else focusResult(i-resultColumns);
    }else if(k==LogicalKeyboardKey.arrowDown){
      if(i+resultColumns<widget.movies.length)focusResult(i+resultColumns);
    }else return KeyEventResult.ignored;
    return KeyEventResult.handled;
  }
  KeyEventResult hardware(FocusNode _,KeyEvent e){
    if(!pressed(e)||nativeOpen||!widget.engine.tv)return KeyEventResult.ignored;
    if(e.logicalKey==LogicalKeyboardKey.backspace){erase();return KeyEventResult.handled;}
    final ch=e.character;
    if(ch!=null&&RegExp(r'^[a-zA-Z0-9 ._\-]$').hasMatch(ch)){
      append(ch);return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  @override void didUpdateWidget(covariant CinemaSearchPage oldWidget){
    super.didUpdateWidget(oldWidget);
    final ids=widget.movies.map((m)=>m.id).toSet();
    final obsolete=resultNodes.keys.where((id)=>!ids.contains(id)).toList();
    if(obsolete.isNotEmpty){
      final lostFocus=obsolete.any((id)=>resultNodes[id]!.hasFocus);
      final removed=obsolete.map((id)=>resultNodes.remove(id)!).toList();
      WidgetsBinding.instance.addPostFrameCallback((_){
        for(final n in removed)n.dispose();
        if(mounted&&lostFocus)focusKeyboard();
      });
    }
  }
  @override void dispose(){
    for(final n in keys)n.dispose();
    for(final n in resultNodes.values)n.dispose();
    nativeKey.dispose();scroll.dispose();super.dispose();
  }
  Widget keyTile(int i,String label,{IconData? icon})=>RemoteTile(
    key:ValueKey('search-key-$i'),label:label,focusNode:keys[i],
    revealOnFocus:false,onFocused:()=>lastKey=i,onPressed:()=>activate(i),
    child:ColoredBox(color:CinemaColors.panel,child:Center(child:icon==null
      ?Text(label,style:TextStyle(fontSize:i<36?19:12,fontWeight:FontWeight.w600))
      :Icon(icon,size:20))));
  Widget keyboard()=>Focus(canRequestFocus:false,onKeyEvent:keyboardEvent,
    child:LayoutBuilder(builder:(context,box){
      final keyHeight=((box.maxHeight-112)/7).clamp(30.0,52.0).toDouble();
      return SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        ValueListenableBuilder<TextEditingValue>(valueListenable:widget.controller,builder:(_,value,__)=>Container(
          height:52,padding:const EdgeInsets.symmetric(horizontal:12),
          decoration:BoxDecoration(color:CinemaColors.panel,borderRadius:BorderRadius.circular(8)),
          child:Row(children:[const Icon(Icons.search,size:20),const SizedBox(width:8),
            Expanded(child:Text(value.text.isEmpty?'Find a movie...':value.text,maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontSize:18,color:value.text.isEmpty?CinemaColors.muted:CinemaColors.ink)))]))),
        const SizedBox(height:6),
        SizedBox(height:40,child:RemoteTile(focusNode:nativeKey,label:'Use TV keyboard',revealOnFocus:false,
          onPressed:openNative,child:const Center(child:Row(mainAxisSize:MainAxisSize.min,children:[
            Icon(Icons.keyboard_outlined,size:19),SizedBox(width:7),Text('Use TV keyboard',style:TextStyle(fontSize:12))])))),
        for(int row=0;row<6;row++)Row(children:[
          for(int col=0;col<6;col++)Expanded(child:SizedBox(height:keyHeight,child:keyTile(row*6+col,letters[row*6+col]))),
        ]),
        Row(children:[
          Expanded(child:SizedBox(height:keyHeight,child:keyTile(36,'Space'))),
          Expanded(child:SizedBox(height:keyHeight,child:keyTile(37,'Backspace',icon:Icons.backspace_outlined))),
          Expanded(child:SizedBox(height:keyHeight,child:keyTile(38,'Clear'))),
          Expanded(child:SizedBox(height:keyHeight,child:keyTile(39,'Results',icon:Icons.arrow_forward))),
        ]),
      ]));
    }));
  Widget resultCard(Movie movie,bool tv)=>RemoteTile(
    key:ValueKey(movie.id),focusNode:tv?resultNode(movie):null,label:movie.title,
    onFocused:()=>lastResult=widget.movies.indexWhere((m)=>m.id==movie.id),
    onPressed:()=>widget.onOpen(movie),
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Expanded(child:Stack(fit:StackFit.expand,children:[
        CinemaArt(movie.poster,cacheWidth:360),
        Positioned(top:5,left:5,child:PlatformPill(engine:widget.engine,movie:movie)),
      ])),
      Padding(padding:const EdgeInsets.fromLTRB(4,4,4,3),child:Text(movie.title,
        maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:tv?14:12))),
    ]));
  Widget resultsPanel(bool tv)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
      Expanded(child:Text(widget.controller.text.trim().isEmpty?'Popular movies':'Search results',
        style:TextStyle(fontSize:tv?22:18,fontWeight:FontWeight.w700))),
      if(widget.busy)const SizedBox(width:17,height:17,child:CircularProgressIndicator(strokeWidth:2)),
    ]),
    if(widget.error!=null)Padding(padding:const EdgeInsets.only(top:6),child:Text(widget.error!,style:const TextStyle(color:CinemaColors.muted,fontSize:12))),
    const SizedBox(height:10),
    Expanded(child:widget.movies.isEmpty
      ?Center(child:Text(widget.busy?'Searching...':widget.controller.text.trim().isEmpty?'Popular movies will appear here':'No movies found',
          style:const TextStyle(color:CinemaColors.muted)))
      :Focus(canRequestFocus:false,onKeyEvent:tv?resultEvent:null,child:LayoutBuilder(builder:(context,box){
        final count=(box.maxWidth/(tv?145:120)).floor().clamp(tv?2:2,6).toInt();
        resultColumns=count;
        final width=(box.maxWidth-(count-1)*8)/count;
        resultStride=width/.64+8;
        return GridView.builder(controller:scroll,padding:const EdgeInsets.only(bottom:8),
          gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:count,
            childAspectRatio:.64,mainAxisSpacing:8,crossAxisSpacing:8),
          itemCount:widget.movies.length,
          findChildIndexCallback:(key){
            if(key is! ValueKey<String>)return null;
            final i=widget.movies.indexWhere((m)=>m.id==key.value);
            return i<0?null:i;
          },
          itemBuilder:(_,i)=>resultCard(widget.movies[i],tv));
      }))),
    const Text('Streaming availability: JustWatch via TMDB',style:TextStyle(fontSize:10,color:CinemaColors.muted)),
  ]);
  @override Widget build(BuildContext context){
    final tv=widget.engine.tv;
    return Padding(padding:EdgeInsets.fromLTRB(tv?40:16,8,tv?40:16,8),
      child:tv?Focus(canRequestFocus:false,onKeyEvent:hardware,child:LayoutBuilder(builder:(context,box){
        final left=(box.maxWidth*.36).clamp(210.0,380.0).toDouble();
        return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:left,height:box.maxHeight,child:keyboard()),
          const SizedBox(width:24),
          Expanded(child:resultsPanel(true)),
        ]);
      })):Column(children:[
        TextField(controller:widget.controller,onChanged:widget.onQuery,maxLength:120,
          textInputAction:TextInputAction.search,
          decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Find a movie',counterText:'',
            suffixIcon:IconButton(icon:const Icon(Icons.clear),tooltip:'Clear search',onPressed:()=>change('')))),
        const SizedBox(height:14),
        Expanded(child:resultsPanel(false)),
      ]));
  }
}
