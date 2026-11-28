import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design.dart';
import '../back_navigation.dart';

/// Shared chrome only: each release owns its body and confirmation behavior.
class WhatsNewDialog extends StatelessWidget {
  final String version;
  final bool upgraded, busy;
  final Widget content;
  final Widget headerGraphic;
  final String? heading, subtitle;
  final String continueLabel;
  final VoidCallback? onContinue;
  const WhatsNewDialog({super.key, required this.version, required this.upgraded,
    required this.content, required this.onContinue, this.busy=false,
    this.heading,this.subtitle,this.continueLabel='Continue',
    this.headerGraphic=const Icon(Icons.check_circle_outline,size:44,color:Color(0xFF83C995))});

  @override Widget build(BuildContext context)=>BackNavigationScope(
    onBack:(){if(!busy)onContinue?.call();},
    child:Shortcuts(shortcuts:const {
      SingleActivator(LogicalKeyboardKey.select,includeRepeats:false):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter,includeRepeats:false):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter,includeRepeats:false):ActivateIntent(),
    },child:AlertDialog(
      constraints:const BoxConstraints(maxWidth:540),
      insetPadding:const EdgeInsets.symmetric(horizontal:20,vertical:16),
      scrollable:true,
      backgroundColor:CinemaColors.panel,
      title:Column(mainAxisSize:MainAxisSize.min,children:[
        headerGraphic,
        const SizedBox(height:8),
        Text(heading??(upgraded?"You're up to date!":"Welcome to isme.gg"),textAlign:TextAlign.center),
        const SizedBox(height:4),
        Text(subtitle??(upgraded?'Successfully updated to v$version':'Version $version'),
          textAlign:TextAlign.center,style:const TextStyle(fontSize:13,color:CinemaColors.muted)),
      ]),
      content:SizedBox(width:460,child:content),
      actions:[SizedBox(width:double.infinity,child:FilledButton(
        autofocus:true,
        style:ButtonStyle(
          minimumSize:const WidgetStatePropertyAll(Size(0,48)),
          side:WidgetStateProperty.resolveWith((states)=>BorderSide(
            color:states.contains(WidgetState.focused)?CinemaColors.ink:Colors.transparent,width:3)),
        ),
        onPressed:busy?null:onContinue,
        child:Text(busy?'Saving…':continueLabel)))],
    )));
}
