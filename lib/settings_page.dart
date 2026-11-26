import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_preferences.dart';
import 'back_navigation.dart';
import 'design.dart';
import 'engine.dart';
import 'support_menu.dart';

/// Shared settings route. Returns true only when the user requests updates,
/// so the caller can release the support UI guard before checking.
class SettingsPage extends StatefulWidget {
  final NativeEngine engine;
  final History history;
  const SettingsPage({super.key,required this.engine,required this.history});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage>{
  bool busy=false;
  NativeEngine get engine=>widget.engine;
  History get history=>widget.history;
  bool get tv=>engine.tv;
  void notice(String message){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
  Future<void> run(Future<void> Function() action,{String? success}) async{
    if(busy)return;
    setState(()=>busy=true);
    try{await action();if(success!=null)notice(success);}
    catch(_){notice('Could not save changes. Please try again.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> saveBool(String key,bool value)=>run(()async{
    if(!await history.prefs.setBool(key,value))throw StateError('Preference write failed');
  });
  Future<T?> choose<T>(String title,Map<T,String> choices,T selected)=>showDialog<T>(
    context:context,builder:(ctx)=>Shortcuts(shortcuts:const {
      SingleActivator(LogicalKeyboardKey.select,includeRepeats:false):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter,includeRepeats:false):ActivateIntent(),
    },child:SimpleDialog(title:Text(title),children:[
      for(final item in choices.entries)TextButton(autofocus:item.key==selected,
        onPressed:()=>Navigator.pop(ctx,item.key),
        child:Row(children:[Expanded(child:Text(item.value)),if(item.key==selected)const Icon(Icons.check)])),
    ])));
  Future<void> language() async{
    final value=await choose('Preferred subtitle language',AppPreferences.languages,AppPreferences.subtitles(history.prefs));
    if(value!=null&&mounted)await run(()async{
      if(!await history.prefs.setString(AppPreferences.subtitleLanguageKey,value))throw StateError('Preference write failed');
    });
  }
  Future<void> size() async{
    final value=await choose('Subtitle size',AppPreferences.sizes.asMap(),AppPreferences.size(history.prefs));
    if(value!=null&&mounted)await run(()async{
      if(!await history.prefs.setInt(AppPreferences.subtitleSizeKey,value))throw StateError('Preference write failed');
    });
  }
  Future<void> region() async{
    final value=await choose('Availability region',AppPreferences.regions,engine.providerCountry);
    if(value!=null&&mounted&&value!=engine.providerCountry)await run(()async{
      if(!await history.prefs.setString(AppPreferences.regionKey,value))throw StateError('Preference write failed');
      await engine.configureMetadata(value,null);
    });
  }
  Future<void> clearHistory() async{
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>Shortcuts(shortcuts:const {
      SingleActivator(LogicalKeyboardKey.select,includeRepeats:false):ActivateIntent(),
    },child:AlertDialog(title:const Text('Clear watch history?'),
      content:const Text('Remove all watch progress and Continue Watching entries on this device. My List will be kept.'),
      actions:[TextButton(autofocus:true,onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Clear history'))])));
    if(yes==true&&mounted)await run(history.clear,success:'Watch history cleared');
  }
  Widget section(String title)=>Padding(padding:const EdgeInsets.fromLTRB(16,24,16,6),
    child:Text(title.toUpperCase(),style:const TextStyle(fontSize:12,letterSpacing:1.5,fontWeight:FontWeight.w700,color:CinemaColors.accent)));
  Widget row(IconData icon,String title,VoidCallback action,{String? subtitle,Widget? trailing,bool danger=false})=>
    _SettingsRow(icon:icon,title:title,subtitle:subtitle,trailing:trailing,danger:danger,onTap:busy?null:action);
  Widget toggle(IconData icon,String title,String subtitle,bool value,ValueChanged<bool> change)=>
    row(icon,title,()=>change(!value),subtitle:subtitle,trailing:IgnorePointer(child:ExcludeFocus(
      child:Switch(value:value,onChanged:busy?null:change))));
  @override Widget build(BuildContext context){
    final p=history.prefs;
    return BackNavigationScope(child:Scaffold(
      appBar:AppBar(title:const Text('Settings'),leading:IconButton(autofocus:tv,tooltip:'Back',
        icon:const Icon(Icons.arrow_back),onPressed:()=>Navigator.maybePop(context))),
      body:SafeArea(child:Shortcuts(shortcuts:const {
        SingleActivator(LogicalKeyboardKey.select,includeRepeats:false):ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter,includeRepeats:false):ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter,includeRepeats:false):ActivateIntent(),
      },child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760),child:ListView(
        padding:EdgeInsets.fromLTRB(tv?24:8,0,tv?24:8,24),children:[
          if(busy)const LinearProgressIndicator(),
          section('Playback'),
          toggle(Icons.play_circle_outline,'Autoplay next episode','Continue to the next episode automatically',AppPreferences.autoplay(p),(v)=>saveBool(AppPreferences.autoplayKey,v)),
          toggle(Icons.monitor_outlined,'Keep screen awake','Prevent sleep during playback',AppPreferences.awake(p),(v)=>saveBool(AppPreferences.awakeKey,v)),
          section('Subtitles'),
          row(Icons.translate,'Preferred subtitle language',language,subtitle:'English or Filipino; availability varies',trailing:Text(AppPreferences.languages[AppPreferences.subtitles(p)]!)),
          row(Icons.format_size,'Subtitle size',size,trailing:Text(AppPreferences.sizes[AppPreferences.size(p)])),
          section('General'),
          row(Icons.public,'Availability region',region,subtitle:'Subscription availability and platform listings',trailing:Text(AppPreferences.regions[engine.providerCountry]??engine.providerCountry)),
          if(tv)toggle(Icons.volume_up_outlined,'Navigation sounds','Play a system click when navigating with the remote',AppPreferences.sounds(p),(v)=>saveBool(AppPreferences.soundKey,v)),
          section('Storage & data'),
          row(Icons.cleaning_services_outlined,'Clear catalog cache',()=>run(()async{
            await engine.clearCatalogCache();
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
          },success:'Catalog cache cleared'),subtitle:'Keep My List, watch progress and preferences'),
          row(Icons.history,'Clear watch history',clearHistory,subtitle:'Remove Continue Watching and resume progress'),
          row(Icons.delete_outline,'Reset app data',()=>confirmClearLocalData(context,engine),danger:true,subtitle:'Remove all local data, including My List'),
          section('Support & about'),
          row(Icons.refresh,'Check for updates',(){appBackGate.block();Navigator.of(context).pop(true);},trailing:Text(installedVersion(engine))),
          row(Icons.report_problem_outlined,'Report a problem',()=>showReportProblem(context,engine)),
          row(Icons.info_outline,'About isme.gg',()=>showAboutDialog(context:context,applicationName:'isme.gg',applicationVersion:installedVersion(engine))),
          row(Icons.description_outlined,'Data credits',()=>showDataCredits(context)),
        ])))))));
  }
}

/// A single focusable target per row on TV; switches are visual indicators.
class _SettingsRow extends StatefulWidget{
  final IconData icon;final String title;final String? subtitle;final Widget? trailing;
  final VoidCallback? onTap;final bool danger;
  const _SettingsRow({required this.icon,required this.title,this.subtitle,this.trailing,this.onTap,this.danger=false});
  @override State<_SettingsRow> createState()=>_SettingsRowState();
}
class _SettingsRowState extends State<_SettingsRow>{
  bool focused=false;
  @override Widget build(BuildContext context)=>FocusableActionDetector(
    enabled:widget.onTap!=null,
    shortcuts:const {SingleActivator(LogicalKeyboardKey.select,includeRepeats:false):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter,includeRepeats:false):ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter,includeRepeats:false):ActivateIntent()},
    actions:{ActivateIntent:CallbackAction<ActivateIntent>(onInvoke:(_){widget.onTap?.call();return null;})},
    onFocusChange:(v){setState(()=>focused=v);if(v)Scrollable.ensureVisible(context,duration:const Duration(milliseconds:160));},
    child:Semantics(button:true,enabled:widget.onTap!=null,child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:widget.onTap,
      child:AnimatedContainer(duration:const Duration(milliseconds:140),margin:const EdgeInsets.symmetric(vertical:2),
        padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
        decoration:BoxDecoration(color:focused?CinemaColors.panel:Colors.transparent,borderRadius:BorderRadius.circular(10),
          border:Border.all(color:focused?CinemaColors.accent:Colors.transparent,width:2)),
        child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Icon(widget.icon,color:widget.danger?Colors.redAccent:CinemaColors.muted),const SizedBox(width:16),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(widget.title,style:TextStyle(fontWeight:FontWeight.w600,color:widget.danger?Colors.redAccent:CinemaColors.ink)),
            if(widget.subtitle!=null)Text(widget.subtitle!,style:const TextStyle(color:CinemaColors.muted,fontSize:12)),
          ])),const SizedBox(width:12),
          // Let the label occupy remaining space; trailing controls keep their
          // intrinsic width and share the same right edge on every row.
          if(widget.trailing!=null)ConstrainedBox(constraints:const BoxConstraints(maxWidth:140),
            child:Align(alignment:Alignment.centerRight,widthFactor:1,
              child:DefaultTextStyle.merge(textAlign:TextAlign.end,child:widget.trailing!)))
          else const Icon(Icons.chevron_right,color:CinemaColors.muted),
        ])))));
}
