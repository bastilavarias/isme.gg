import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_preferences.dart';
import '../../back_navigation.dart';
import '../../design.dart';
import '../whats_new_dialog.dart';

Widget buildV201(SharedPreferences prefs, String version, bool upgraded,
    Future<void> Function() acknowledge)=>PlaybackPatchDialog(
      prefs:prefs,version:version,upgraded:upgraded,acknowledge:acknowledge);

class PlaybackPatchDialog extends StatefulWidget {
  final SharedPreferences prefs;
  final String version;
  final bool upgraded;
  final Future<void> Function() acknowledge;
  const PlaybackPatchDialog({super.key,required this.prefs,required this.version,
    required this.upgraded,required this.acknowledge});
  @override State<PlaybackPatchDialog> createState()=>_PlaybackPatchDialogState();
}

class _PlaybackPatchDialogState extends State<PlaybackPatchDialog> {
  bool busy=false;
  String? error;
  Future<void> confirm() async {
    if(busy)return;
    setState((){busy=true;error=null;});
    try {
      await widget.acknowledge();
      if(mounted)popCurrentPage(context);
    }catch(_){
      if(mounted)setState((){busy=false;error='Could not save. Please try again.';});
    }
  }

  Widget feature(IconData icon,String title,String description)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:6),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,color:CinemaColors.accent,size:22),const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
        Text(description,style:const TextStyle(fontSize:13,color:CinemaColors.muted)),
      ])),
    ]));

  @override Widget build(BuildContext context){
    final direct=AppPreferences.nativeDirect(widget.prefs);
    final fast=direct&&AppPreferences.fastStartup(widget.prefs);
    return WhatsNewDialog(
      version:widget.version,upgraded:widget.upgraded,busy:busy,onContinue:confirm,
      headerGraphic:const Text('🎉',style:TextStyle(fontSize:44,fontFamily:'sans-serif',
        fontFamilyFallback:['Noto Color Emoji'],height:1.2),semanticsLabel:'Celebration'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text("WHAT'S NEW",style:TextStyle(color:CinemaColors.accent,
          fontWeight:FontWeight.w600,fontSize:12,letterSpacing:1.2)),
        const SizedBox(height:6),
        feature(Icons.bolt,'Faster startup','Designed to get you into videos sooner.'),
        feature(Icons.layers_outlined,'Adaptive buffering','Adjusts priorities when the buffer runs low.'),
        feature(Icons.skip_next,'Improved seeking & resume','Designed to recover when jumping between scenes.'),
        const Divider(height:20),
        Text('Native Direct: ${direct?'On':'Off'}  •  Fast Startup: ${fast?'On':'Off'}',
          style:const TextStyle(fontWeight:FontWeight.w600,fontSize:13)),
        const SizedBox(height:4),
        const Text('Both are enabled by default. You can change your playback preferences anytime in Settings.',
          style:TextStyle(fontSize:12,color:CinemaColors.muted)),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(error!,
          style:TextStyle(color:Theme.of(context).colorScheme.error))),
      ]));
  }
}
