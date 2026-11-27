import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/adaptive_buffering.dart';

void main(){
  test('healthy start keeps small buffer while slow reads and resume raise target',(){
    expect(AdaptiveBufferPolicy.startupTargetMs(readWaitMs:100,initMs:800,resuming:false),2500);
    expect(AdaptiveBufferPolicy.startupTargetMs(readWaitMs:5000,initMs:6000,resuming:false),6000);
    expect(AdaptiveBufferPolicy.startupTargetMs(readWaitMs:12000,initMs:100,resuming:false),10000);
    expect(AdaptiveBufferPolicy.startupTargetMs(readWaitMs:0,initMs:100,resuming:true),6000);
  });
  test('only buffer ahead of the playhead counts',(){
    expect(AdaptiveBufferPolicy.aheadMs(positionMs:10000,ranges:[
      (startMs:0,endMs:5000),(startMs:10000,endMs:14000)]),4000);
    expect(AdaptiveBufferPolicy.aheadMs(positionMs:7000,ranges:[
      (startMs:0,endMs:5000),(startMs:10000,endMs:14000)]),0);
    expect(AdaptiveBufferPolicy.aheadMs(positionMs:10000,ranges:[]),isNull);
  });
  test('hold is capped and honors end of media and unknown telemetry',(){
    bool hold(int elapsed,int? ahead,{int remaining=60000,bool buffering=false})=>
      AdaptiveBufferPolicy.shouldHold(elapsedMs:elapsed,aheadMs:ahead,targetMs:6000,
        remainingMs:remaining,buffering:buffering);
    expect(hold(0,2000),isTrue);
    expect(hold(8000,2000,buffering:true),isFalse);
    expect(hold(0,6000),isFalse);
    expect(hold(0,500,remaining:500),isFalse);
    expect(hold(0,0,remaining:0),isFalse);
    expect(hold(0,null),isFalse);
    expect(hold(0,null,buffering:true),isTrue);
    expect(hold(2000,null,buffering:true),isFalse);
  });
  test('runtime buffer hysteresis avoids repeated toggles and respects pause',(){
    bool urgent(bool old,int? ahead,{bool playing=true,bool buffering=false})=>
      AdaptiveBufferPolicy.urgent(previous:old,wantsPlayback:playing,buffering:buffering,aheadMs:ahead);
    expect(urgent(false,2499),isTrue);
    expect(urgent(false,2500),isFalse);
    expect(urgent(true,5999),isTrue);
    expect(urgent(true,6000),isFalse);
    expect(urgent(false,null,buffering:true),isTrue);
    expect(urgent(true,0,playing:false,buffering:true),isFalse);
    expect(urgent(false,null),isFalse);
  });
}
