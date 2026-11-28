import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/playback_screen_guard.dart';

void main() {
  testWidgets('active playback renews and pause releases the screen lease', (tester) async {
    final calls = <bool>[];
    final guard = PlaybackScreenGuard((active) async {
      calls.add(active);
      return active;
    }, onFailure: () => fail('Unexpected native failure'));
    guard.update(true);
    guard.update(true);
    await tester.pump();
    expect(calls, [true]);
    await tester.pump(PlaybackScreenGuard.interval);
    expect(calls, [true, true]);
    guard.update(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, [true, true, false]);
    guard.update(true);
    guard.dispose();
    guard.update(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, [true, true, false, true, false]);
  });

  testWidgets('native failure and mismatched acknowledgment are retried', (tester) async {
    var calls = 0;
    var failures = 0;
    final guard = PlaybackScreenGuard((active) async {
      if (!active) return false;
      calls++;
      if (calls == 1) throw StateError('channel unavailable');
      return calls > 2;
    }, onFailure: () => failures++);
    guard.update(true);
    await tester.pump();
    expect(failures, 1);
    await tester.pump(PlaybackScreenGuard.interval);
    expect(failures, 2);
    await tester.pump(PlaybackScreenGuard.interval);
    expect(calls, 3);
    expect(failures, 2);
    guard.dispose();
    await tester.pump();
  });
}
