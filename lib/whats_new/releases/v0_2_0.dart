import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_preferences.dart';
import '../../design.dart';
import '../whats_new_dialog.dart';

Widget buildV020(SharedPreferences prefs, String version, bool upgraded,
    Future<void> Function() acknowledge)=>PlaybackUpdateDialog(
      prefs:prefs,version:version,upgraded:upgraded,acknowledge:acknowledge);

class PlaybackUpdateDialog extends StatefulWidget {
  final SharedPreferences prefs;
  final String version;
  final bool upgraded;
  final Future<void> Function() acknowledge;
  const PlaybackUpdateDialog({super.key,required this.prefs,required this.version,
    required this.upgraded,required this.acknowledge});
  @override State<PlaybackUpdateDialog> createState()=>_PlaybackUpdateDialogState();
}

class _PlaybackUpdateDialogState extends State<PlaybackUpdateDialog> {
  late bool direct=AppPreferences.nativeDirect(widget.prefs);
  late bool fast=direct&&AppPreferences.fastStartup(widget.prefs);
  bool busy=false;
  String? error;
  Future<void> confirm() async {
    if(busy)return;
    setState((){busy=true;error=null;});
    final prefs=widget.prefs;
    final changes={
      AppPreferences.fastStartupKey:direct&&fast,
      AppPreferences.adaptiveBufferingKey:direct,
      AppPreferences.nativeDirectKey:direct,
    };
    final previous={for(final key in changes.keys)key:prefs.getBool(key)};
    try {
      for(final entry in changes.entries){
        if(!await prefs.setBool(entry.key,entry.value))throw StateError('Preference write failed');
      }
      await widget.acknowledge();
      if(mounted)Navigator.of(context).pop();
    }catch(_){
      for(final entry in previous.entries){
        try {
          if(entry.value==null){await prefs.remove(entry.key);}
          else {await prefs.setBool(entry.key,entry.value!);}
        }catch(_){}
      }
      if(mounted)setState((){busy=false;error='Could not save preferences. Please try again.';});
    }
  }

  Widget feature(IconData icon,String title,String description)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:6),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,color:CinemaColors.accent,size:22),const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
        Text(description,style:const TextStyle(fontSize:12,color:CinemaColors.muted)),
      ])),
    ]));
  Widget label(String text)=>Text(text,style:const TextStyle(
    color:CinemaColors.accent,fontWeight:FontWeight.w600,fontSize:12,letterSpacing:1.2));

  @override Widget build(BuildContext context)=>WhatsNewDialog(
    version:widget.version,upgraded:widget.upgraded,busy:busy,onContinue:confirm,
    headerGraphic:const Text('🎉',style:TextStyle(fontSize:44,fontFamily:'sans-serif',
      fontFamilyFallback:['Noto Color Emoji'],height:1.2),semanticsLabel:'Celebration'),
    content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      label("WHAT'S NEW"),const SizedBox(height:8),
      const Text('A new playback experience.',style:TextStyle(fontSize:20,fontWeight:FontWeight.w700)),
      const SizedBox(height:4),
      const Text('Try our experimental next-generation playback engine.',
        style:TextStyle(fontSize:13,color:CinemaColors.muted)),
      const SizedBox(height:8),
      feature(Icons.bolt,'Faster startup','Designed to get you into your videos sooner.'),
      feature(Icons.layers_outlined,'Adaptive buffering','Adjusts priorities when the playback buffer runs low.'),
      feature(Icons.skip_next,'Improved seeking & resume','Designed to recover when jumping between scenes.'),
      const Divider(height:24),
      label('TRY THE NEW ENGINE'),
      CheckboxListTile(
        autofocus:true,contentPadding:EdgeInsets.zero,controlAffinity:ListTileControlAffinity.leading,
        title:const Text('Enable Native Direct'),
        subtitle:const Text('Experimental native playback with adaptive buffering.'),
        value:direct,onChanged:busy?null:(value)=>setState((){direct=value??false;if(!direct)fast=false;})),
      CheckboxListTile(
        contentPadding:EdgeInsets.zero,controlAffinity:ListTileControlAffinity.leading,
        title:const Text('Enable Fast Startup'),
        subtitle:const Text('Prioritize initial media data for faster loading.'),
        value:direct&&fast,onChanged:busy||!direct?null:(value)=>setState(()=>fast=value??false)),
      const SizedBox(height:8),
      const Text('Optional. Keep Legacy HTTP by leaving Native Direct unchecked. Change these anytime in Settings. Performance may vary by device and connection.',
        style:TextStyle(fontSize:12,color:CinemaColors.muted)),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(error!,
        style:TextStyle(color:Theme.of(context).colorScheme.error))),
    ]));
}
