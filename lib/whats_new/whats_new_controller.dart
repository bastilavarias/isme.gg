import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine.dart';
import 'whats_new_registry.dart';

class WhatsNewController {
  static const acknowledgedKey='isme-whats-new-acknowledged-code';
  static WhatsNewBuilder? builder(String version,int code)=>whatsNewRegistry['$version+$code'];
  static bool pending(SharedPreferences prefs,String version,int code)=>
    builder(version,code)!=null&&(prefs.getInt(acknowledgedKey)??0)<code;

  static Future<void> show(BuildContext context,SharedPreferences prefs,{
    required String version,required int code,required bool upgraded,bool preview=false,
  }) async {
    final build=builder(version,code);
    if(build==null||(!preview&&!pending(prefs,version,code)))return;
    await showDialog<void>(context:context,barrierDismissible:false,
      builder:(_)=>build(prefs,version,upgraded,()async{
        if(!preview&&!await prefs.setInt(acknowledgedKey,code)){
          throw StateError('Could not acknowledge release');
        }
      }));
  }
}

/// Runs once per home mount, after a Navigator exists. The updater is held
/// while the release dialog is active, so it cannot cover the modal.
class WhatsNewGate extends StatefulWidget {
  final NativeEngine engine;
  final SharedPreferences prefs;
  final Widget child;
  const WhatsNewGate({super.key,required this.engine,required this.prefs,required this.child});
  @override State<WhatsNewGate> createState()=>_WhatsNewGateState();
}
class _WhatsNewGateState extends State<WhatsNewGate> {
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_)=>present());
  }
  Future<void> present() async {
    final e=widget.engine,p=widget.prefs;
    try{
      if(!mounted)return;
      if(!WhatsNewController.pending(p,e.appVersion,e.appVersionCode))return;
      await WhatsNewController.show(context,p,version:e.appVersion,code:e.appVersionCode,upgraded:e.isUpgrade);
    }finally{await e.setSupportUiActive(false);}
  }
  @override Widget build(BuildContext context)=>widget.child;
}
