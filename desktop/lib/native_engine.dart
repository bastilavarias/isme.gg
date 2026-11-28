import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

/// One private child process per playback. No remote media server.
class DesktopNativeEngine {
  final _client=http.Client();
  Process? _process;
  Directory? _cache;
  Uri? _origin;
  String _token='';
  bool _closed=false;
  Map<String,String> get headers=>{'x-isme-token':_token};
  bool get connected=>_origin!=null&&!_closed;

  static Directory engineDirectory(){
    final override=Platform.environment['ISME_DESKTOP_ENGINE'];
    if(override!=null&&override.isNotEmpty)return Directory(override);
    final sep=Platform.pathSeparator;
    final bundled=Directory('${File(Platform.resolvedExecutable).parent.path}${sep}engine');
    if(bundled.existsSync())return bundled;
    final fromDesktop=Directory('native-engine${sep}target');
    if(fromDesktop.existsSync())return fromDesktop;
    return Directory('desktop${sep}native-engine${sep}target');
  }
  static bool get available {
    final dir=engineDirectory(),sep=Platform.pathSeparator;
    return Directory('${dir.path}${sep}classes').existsSync()&&
      Directory('${dir.path}${sep}dependency').existsSync();
  }
  Future<void> connect()async{
    if(_closed)throw StateError('Engine closed');
    final dir=engineDirectory().absolute,sep=Platform.pathSeparator;
    if(!available)throw StateError('Desktop native engine has not been prepared.');
    final cache=await Directory.systemTemp.createTemp('isme-session-');
    _cache=cache;
    if(_closed){await cache.delete(recursive:true);throw StateError('Engine closed');}
    final rng=Random.secure();
    _token=List.generate(32,(_)=>rng.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
    final runtime=File('${dir.path}${sep}runtime${sep}bin${sep}${Platform.isWindows?'java.exe':'java'}');
    final javaHome=Platform.environment['JAVA_HOME'];
    final installed=javaHome==null?null:File('$javaHome${sep}bin${sep}${Platform.isWindows?'java.exe':'java'}');
    final java=runtime.existsSync()?runtime.path:installed!=null&&installed.existsSync()?installed.path:'java';
    try{
      final process=await Process.start(java,[
        '-cp','${dir.path}${sep}classes${Platform.isWindows?';':':'}${dir.path}${sep}dependency${sep}*',
        'gg.isme.desktop.DesktopServer',
      ],environment:{'ISME_DESKTOP_TOKEN':_token,'ISME_DESKTOP_CACHE':cache.path});
      _process=process;
      if(_closed){process.kill();await process.exitCode;try{await cache.delete(recursive:true);}catch(_){}throw StateError('Engine closed');}
      unawaited(process.stderr.drain<void>());
      final handshake=Completer<Map<String,dynamic>>();
      final output=process.stdout.transform(utf8.decoder).transform(const LineSplitter());
      output.listen((line){
        if(handshake.isCompleted)return;
        try{
          final value=jsonDecode(line);
          if(value is Map<String,dynamic>&&value['protocol']==1)handshake.complete(value);
        }catch(_){}
      },onError:(Object error){if(!handshake.isCompleted)handshake.completeError(error);},
        onDone:(){if(!handshake.isCompleted)handshake.completeError(StateError('Native engine exited'));});
      final data=await handshake.future.timeout(const Duration(seconds:20));
      final port=data['port'];
      if(port is! int||port<1||port>65535||_closed)throw StateError('Invalid engine connection');
      _origin=Uri(scheme:'http',host:'127.0.0.1',port:port);
    }catch(_){await close();rethrow;}
  }
  Future<Map<String,dynamic>> request(String path,{Map<String,dynamic>? body})async{
    if(!connected)throw StateError('Engine disconnected');
    final uri=_origin!.resolve(path);
    final response=await (body==null?_client.get(uri,headers:headers):
      _client.post(uri,headers:{...headers,'content-type':'application/json'},body:jsonEncode(body)))
      .timeout(const Duration(seconds:12));
    if(response.statusCode!=200)throw StateError('Native engine request failed');
    return jsonDecode(response.body) as Map<String,dynamic>;
  }
  Uri streamUri(String path){
    final uri=_origin!.resolve(path);
    if(uri.origin!=_origin!.origin||uri.path!='/stream/video')throw StateError('Invalid stream');
    return uri;
  }
  Future<void> close()async{
    if(_closed)return;
    _closed=true;_client.close();
    final process=_process;
    if(process!=null){
      try{await process.stdin.close().timeout(const Duration(seconds:2));}catch(_){}
      try{await process.exitCode.timeout(const Duration(seconds:5));}
      on TimeoutException{process.kill();await process.exitCode.timeout(const Duration(seconds:5));}
    }
    final cache=_cache;
    if(cache!=null){try{await cache.delete(recursive:true);}catch(_){}}
  }
}
