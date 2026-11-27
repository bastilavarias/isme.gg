import 'dart:math' as math;

/// Best-effort startup guard and runtime low-buffer hysteresis. Values are
/// experimental tuning knobs, not a throughput guarantee.
class AdaptiveBufferPolicy {
  static const maxStartupHoldMs=8000;
  static const lowBufferMs=2500;
  static const recoveredBufferMs=6000;

  static int startupTargetMs({required int readWaitMs,required int initMs,
      required bool resuming}){
    final delay=math.max(readWaitMs,initMs);
    if(delay>=10000)return 10000;
    if(delay>=3000||resuming)return 6000;
    return 2500;
  }

  static int? aheadMs({required int positionMs,required Iterable<({int startMs,int endMs})> ranges}){
    if(ranges.isEmpty)return null;
    var ahead=0;
    for(final range in ranges){
      if(range.startMs<=positionMs&&range.endMs>=positionMs){
        ahead=math.max(ahead,range.endMs-positionMs);
      }
    }
    return ahead;
  }

  static bool shouldHold({required int elapsedMs,required int? aheadMs,
      required int targetMs,required int remainingMs,required bool buffering}){
    if(elapsedMs>=maxStartupHoldMs||remainingMs<=0)return false;
    // Missing telemetry must not introduce a fixed wait on healthy starts.
    if(aheadMs==null)return buffering&&elapsedMs<2000;
    return buffering||aheadMs<math.min(targetMs,remainingMs);
  }

  static bool urgent({required bool previous,required bool wantsPlayback,
      required bool buffering,required int? aheadMs}){
    if(!wantsPlayback)return false;
    if(buffering)return true;
    if(aheadMs==null)return false;
    return aheadMs<(previous?recoveredBufferMs:lowBufferMs);
  }
}
