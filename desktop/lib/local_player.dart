import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Plays only the local file explicitly selected by the user.
class DesktopLocalPlayer extends StatefulWidget {
  final String path;
  const DesktopLocalPlayer({super.key,required this.path});
  @override State<DesktopLocalPlayer> createState()=>_DesktopLocalPlayerState();
}
class _DesktopLocalPlayerState extends State<DesktopLocalPlayer>{
  late final Player player;
  late final VideoController controller;
  StreamSubscription<String>? errors;
  String? error;
  bool opening=true;
  @override void initState(){
    super.initState();
    player=Player();
    controller=VideoController(player);
    errors=player.stream.error.listen((message){
      if(mounted)setState(()=>error='Playback failed. Check the video format and file.');
    });
    unawaited(start());
  }
  Future<void> start()async{
    try{
      if(!await File(widget.path).exists())throw StateError('File missing');
      if(!mounted)return;
      await player.open(Media(Uri.file(widget.path,windows:Platform.isWindows).toString()));
    }catch(_){
      if(mounted)setState(()=>error='Could not open this video.');
    }finally{
      if(mounted)setState(()=>opening=false);
    }
  }
  @override void dispose(){
    unawaited(errors?.cancel());
    unawaited(player.dispose());
    super.dispose();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Local playback')),
    body:Stack(fit:StackFit.expand,children:[
      Video(controller:controller),
      if(opening&&error==null)const Center(child:CircularProgressIndicator()),
      if(error!=null)Center(child:Card(child:Padding(
        padding:const EdgeInsets.all(24),child:Text(error!)))),
    ]),
  );
}
