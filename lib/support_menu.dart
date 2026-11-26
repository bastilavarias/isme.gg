import 'package:flutter/material.dart';
import 'design.dart';
import 'engine.dart';

const reportIssueUrl='https://github.com/bastilavarias/isme.gg/issues/new';
enum SupportAction { report, clear, update }

String installedVersion(NativeEngine engine)=>engine.appVersion.isEmpty?'—':'v${engine.appVersion}';

Widget _menuLabel(String label,IconData icon,{String? trailing})=>Row(children:[
  Icon(icon,size:20,color:CinemaColors.muted),
  const SizedBox(width:12),
  Expanded(child:Text(label)),
  if(trailing!=null)...[const SizedBox(width:12),Text(trailing,style:const TextStyle(fontSize:12,color:CinemaColors.muted))],
]);

List<PopupMenuEntry<SupportAction>> supportMenuItems(NativeEngine engine)=>[
  PopupMenuItem(value:SupportAction.report,child:_menuLabel('Report a problem',Icons.report_problem_outlined)),
  PopupMenuItem(value:SupportAction.clear,child:_menuLabel('Clear local data',Icons.delete_outline)),
  const PopupMenuDivider(),
  PopupMenuItem(value:SupportAction.update,child:_menuLabel('Check updates',Icons.refresh,trailing:installedVersion(engine))),
];

Future<SupportAction?> showSupportSheet(BuildContext context,NativeEngine engine)=>
  showModalBottomSheet<SupportAction>(context:context,showDragHandle:true,isScrollControlled:true,builder:(ctx)=>SafeArea(
    child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.report_problem_outlined),title:const Text('Report a problem'),
        onTap:()=>Navigator.pop(ctx,SupportAction.report)),
      ListTile(leading:const Icon(Icons.delete_outline),title:const Text('Clear local data'),
        onTap:()=>Navigator.pop(ctx,SupportAction.clear)),
      const Divider(height:1,indent:16,endIndent:16),
      ListTile(leading:const Icon(Icons.refresh),title:const Text('Check updates'),
        trailing:Text(installedVersion(engine),style:const TextStyle(color:CinemaColors.muted,fontSize:12)),
        onTap:()=>Navigator.pop(ctx,SupportAction.update)),
    ]))));

/// Keep automatic update prompts out of the menu and confirmation dialogs.
Future<void> openSupportMenu(BuildContext context,NativeEngine engine,Future<SupportAction?> Function() choose) async {
  SupportAction? action;
  await engine.setSupportUiActive(true);
  try{
    if(!context.mounted)return;
    action=await choose();
    if(!context.mounted)return;
    if(action==SupportAction.report){
      await showReportProblem(context,engine);
    }else if(action==SupportAction.clear){
      await confirmClearLocalData(context,engine);
    }
  }finally{
    await engine.setSupportUiActive(false);
  }
  if(action==SupportAction.update&&context.mounted){
    try{await engine.checkUpdates();}
    catch(_){if(context.mounted)ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content:Text('Updates are disabled in this development build.')));}
  }
}

Future<void> showReportProblem(BuildContext context,NativeEngine engine)=>showDialog<void>(
  context:context,
  builder:(ctx)=>AlertDialog(
    title:const Text('Report a problem'),
    scrollable:true,
    content:SizedBox(width:340,child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Something not working? Scan the QR code to report a problem on GitHub.',textAlign:TextAlign.center),
      const SizedBox(height:16),
      Semantics(label:'QR code for the isme.gg GitHub issue form',image:true,
        child:const SizedBox.square(dimension:184,child:CustomPaint(painter:_IssueQrPainter()))),
      const SizedBox(height:12),
      const SelectableText(reportIssueUrl,textAlign:TextAlign.center,
        style:TextStyle(color:CinemaColors.muted,fontSize:11)),
      const SizedBox(height:8),
      const Text('GitHub sign-in may be required. No app data is sent automatically.',
        textAlign:TextAlign.center,style:TextStyle(color:CinemaColors.muted,fontSize:11)),
      TextButton(onPressed:()=>showDataCredits(ctx),child:const Text('Data credits')),
    ])),
    actions:[
      if(!engine.tv)TextButton(onPressed:()async{
        try{await engine.openIssueReport();}
        catch(_){if(ctx.mounted)ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content:Text('No browser available. Use the QR code or link.')));}
      },child:const Text('Open in browser')),
      FilledButton(autofocus:true,onPressed:()=>Navigator.pop(ctx),child:const Text('Close')),
    ],
  ));

// Consolidated credits rather than a footer on every browsing screen.
Future<void> showDataCredits(BuildContext context)=>showDialog<void>(
  context:context,builder:(ctx)=>AlertDialog(
    title:const Text('Data credits'),scrollable:true,
    content:SizedBox(width:360,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('isme.gg',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),
      const SizedBox(height:16),
      Image.network('https://upload.wikimedia.org/wikipedia/commons/thumb/8/89/Tmdb.new.logo.svg/330px-Tmdb.new.logo.svg.png',
        height:54,fit:BoxFit.contain,semanticLabel:'The Movie Database logo',
        errorBuilder:(_,__,___)=>const Text('The Movie Database (TMDB)',style:TextStyle(fontWeight:FontWeight.w700))),
      const SizedBox(height:8),
      const Text('This product uses the TMDB API but is not endorsed or certified by TMDB.'),
      const SizedBox(height:6),
      const SelectableText('https://www.themoviedb.org',style:TextStyle(color:CinemaColors.muted,fontSize:11)),
      const SizedBox(height:12),
      const Text('Streaming availability data: JustWatch via TMDB. Additional catalog metadata: Cinemeta.'),
      const SizedBox(height:6),
      const Text('Weekly rankings reflect TMDB trending order, not isme.gg viewing statistics.'),
      const SizedBox(height:8),
      const SelectableText('Logo: Travis Bell / TMDB, CC BY-SA 4.0. Unmodified artwork. https://creativecommons.org/licenses/by-sa/4.0/',
        style:TextStyle(color:CinemaColors.muted,fontSize:10)),
    ])),
    actions:[FilledButton(autofocus:true,onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))],
  ));

Future<void> confirmClearLocalData(BuildContext context,NativeEngine engine) async {
  final confirmed=await showDialog<bool>(
    context:context,barrierDismissible:false,
    builder:(ctx)=>AlertDialog(
      title:const Text('Clear local data?'),
      scrollable:true,
      content:const SizedBox(width:340,child:Text(
        'Permanently remove watch history, playback progress, cached files, saved credentials and preferences on this device. '
        'The app will close and you can reopen it with default settings. This cannot be undone.')),
      actions:[
        TextButton(autofocus:true,onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(style:FilledButton.styleFrom(backgroundColor:const Color(0xFFB91C1C),foregroundColor:Colors.white),
          onPressed:()=>Navigator.pop(ctx,true),child:const Text('Clear data')),
      ],
    ));
  if(confirmed!=true||!context.mounted)return;
  try{
    if(!await engine.clearLocalData())throw StateError('Reset not accepted');
  }catch(_){
    if(context.mounted)ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content:Text('Could not clear local data. Please try again.')));
  }
}

// Precomputed QR Model 2, error correction M, including the four-module quiet zone.
// Encodes reportIssueUrl exactly. No network request, asset or runtime dependency.
const issueQrModules=<String>[
  '00000000000000000000000000000000000000000',
  '00000000000000000000000000000000000000000',
  '00000000000000000000000000000000000000000',
  '00000000000000000000000000000000000000000',
  '00001111111001111000100111010011111110000',
  '00001000001000001001001011100010000010000',
  '00001011101011111010000001100010111010000',
  '00001011101011000001001000100010111010000',
  '00001011101010100111100011010010111010000',
  '00001000001010011000011100000010000010000',
  '00001111111010101010101010101011111110000',
  '00000000000011111010100111011000000000000',
  '00001011111000110110110100000011111000000',
  '00001011010110011100110111010011011010000',
  '00001000111011110111110001101100101100000',
  '00001110000110010101011101101110111110000',
  '00001010001101000011100000110101110110000',
  '00000100110111001001001000110010000110000',
  '00000010111011110101100010100111111100000',
  '00001000000011111001001111011110111000000',
  '00001101001000110001010000101101110010000',
  '00001001100111101100101111010011011010000',
  '00000100111101110111001010001101101000000',
  '00000110010100010000100111100111111110000',
  '00001101101110101011001110000001110000000',
  '00001001010111101011110111010011001010000',
  '00001011011000111010001010000100010100000',
  '00001010100111011000100011101110011110000',
  '00001001001010110100110000111111100000000',
  '00000000000010001000111100011000101110000',
  '00001111111001001101110010111010101100000',
  '00001000001011011001011011111000111100000',
  '00001011101010001101100100101111110000000',
  '00001011101010000001011110011100110110000',
  '00001011101010100101100000100011011000000',
  '00001000001001100011001111100110111000000',
  '00001111111010010001010100111111000100000',
  '00000000000000000000000000000000000000000',
  '00000000000000000000000000000000000000000',
  '00000000000000000000000000000000000000000',
  '00000000000000000000000000000000000000000',
];
class _IssueQrPainter extends CustomPainter {
  const _IssueQrPainter();
  @override void paint(Canvas canvas,Size size){
    canvas.drawRect(Offset.zero&size,Paint()..color=Colors.white);
    final count=issueQrModules.length;
    final module=(size.shortestSide/count).floorToDouble();
    if(module<=0)return;
    final x=((size.width-module*count)/2).floorToDouble(),y=((size.height-module*count)/2).floorToDouble();
    final ink=Paint()..color=Colors.black..isAntiAlias=false;
    for(var row=0;row<count;row++){
      for(var col=0;col<count;col++){
        if(issueQrModules[row][col]=='1')canvas.drawRect(Rect.fromLTWH(x+col*module,y+row*module,module,module),ink);
      }
    }
  }
  @override bool shouldRepaint(covariant _IssueQrPainter oldDelegate)=>false;
}
