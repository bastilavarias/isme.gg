import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../back_navigation.dart';
import '../../design.dart';
import '../../playback_mascot.dart';
import '../whats_new_dialog.dart';

Widget buildV210(SharedPreferences prefs,String version,bool upgraded,
    Future<void> Function() acknowledge)=>MeetIsmeDialog(
      version:version,upgraded:upgraded,acknowledge:acknowledge);

class MeetIsmeDialog extends StatefulWidget {
  final String version;
  final bool upgraded;
  final Future<void> Function() acknowledge;
  const MeetIsmeDialog({super.key,required this.version,required this.upgraded,
    required this.acknowledge});
  @override State<MeetIsmeDialog> createState()=>_MeetIsmeDialogState();
}
class _MeetIsmeDialogState extends State<MeetIsmeDialog>{
  bool busy=false;
  String? error;
  Future<void> confirm() async{
    if(busy)return;
    setState((){busy=true;error=null;});
    try{
      await widget.acknowledge();
      if(mounted)popCurrentPage(context);
    }catch(_){
      if(mounted)setState((){busy=false;error='Could not save. Please try again.';});
    }
  }
  Widget feature(IconData icon,String title,String detail)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:5),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,size:22,color:CinemaColors.accent),const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),
        Text(detail,style:const TextStyle(fontSize:13,color:CinemaColors.muted)),
      ])),
    ]));
  @override Widget build(BuildContext context)=>WhatsNewDialog(
    version:widget.version,upgraded:widget.upgraded,busy:busy,onContinue:confirm,
    heading:'Meet Isme! 🐾',subtitle:'Your movie companion has arrived.',
    continueLabel:'Enjoy the show!',
    headerGraphic:MediaQuery(
      data:MediaQuery.of(context).copyWith(disableAnimations:true),
      child:const PlaybackMascot(pose:IsmePlaybackPose.starting,size:88)),
    content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('ISME.GG · VERSION ${widget.version}',style:const TextStyle(
        fontSize:11,fontWeight:FontWeight.w700,color:CinemaColors.accent,letterSpacing:1)),
      const Divider(height:16),
      feature(Icons.pets,'Meet our official mascot','Animated playback visuals inspired by the real Isme.'),
      feature(Icons.palette_outlined,'A fresh identity','New logo and refreshed branding.'),
      feature(Icons.grid_view_rounded,'Cleaner platform icons','Recognizable, consistently sized service icons.'),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(error!,
        style:TextStyle(color:Theme.of(context).colorScheme.error))),
    ]));
}
