import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CinemaColors {
  static const canvas=Color(0xFF11110F), panel=Color(0xFF24211F), accent=Color(0xFFF3A369),
      ink=Color(0xFFF5F1EB), muted=Color(0xFFB7AFA7), black=Color(0xFF000000);
}
ThemeData cinemaTheme() => ThemeData(
  brightness:Brightness.dark, scaffoldBackgroundColor:CinemaColors.canvas,
  colorScheme: const ColorScheme.dark(primary:CinemaColors.accent,onPrimary:CinemaColors.canvas,surface:CinemaColors.panel),
  fontFamily:null, useMaterial3:true,
  textTheme: const TextTheme(bodyMedium:TextStyle(color:CinemaColors.ink)),
  inputDecorationTheme: const InputDecorationTheme(filled:true,fillColor:CinemaColors.panel,border:OutlineInputBorder()),
);
class CinemaArt extends StatelessWidget {
  final String url; final BoxFit fit; final int cacheWidth;
  const CinemaArt(this.url,{super.key,this.fit=BoxFit.cover,this.cacheWidth=480});
  @override Widget build(BuildContext context) => url.startsWith('https://') ? Image.network(url,fit:fit,cacheWidth:cacheWidth,
    errorBuilder:(_,__,___)=>const ColoredBox(color:CinemaColors.panel,child:Center(child:Icon(Icons.movie_outlined,color:CinemaColors.muted)))) :
    const ColoredBox(color:CinemaColors.panel,child:Center(child:Icon(Icons.movie_outlined,color:CinemaColors.muted)));
}
class RemoteTile extends StatefulWidget {
  final Widget child; final VoidCallback onPressed; final VoidCallback? onFocused;
  final bool autofocus, revealOnFocus; final String? label;
  const RemoteTile({super.key,required this.child,required this.onPressed,this.onFocused,this.autofocus=false,this.revealOnFocus=true,this.label});
  @override State<RemoteTile> createState()=>_RemoteTileState();
}
class _RemoteTileState extends State<RemoteTile> {
  bool focused=false;
  @override Widget build(BuildContext context) => FocusableActionDetector(
    autofocus:widget.autofocus,
    shortcuts: const {SingleActivator(LogicalKeyboardKey.select):ActivateIntent(),SingleActivator(LogicalKeyboardKey.enter):ActivateIntent()},
    actions: {ActivateIntent:CallbackAction<ActivateIntent>(onInvoke:(_){widget.onPressed();return null;})},
    onFocusChange:(value){setState(()=>focused=value);if(value){widget.onFocused?.call();if(widget.revealOnFocus)Scrollable.ensureVisible(context,duration:Duration.zero,alignmentPolicy:ScrollPositionAlignmentPolicy.keepVisibleAtEnd);}},
    child:Semantics(button:true,label:widget.label,child:GestureDetector(onTap:widget.onPressed,child:Container(
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(8),border:Border.all(color:focused?CinemaColors.accent:Colors.transparent,width:3)),
      child:ClipRRect(borderRadius:BorderRadius.circular(5),child:widget.child)))));
}
