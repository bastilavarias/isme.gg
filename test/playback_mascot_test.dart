import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/playback_mascot.dart';

void main() {
  test('native states map to distinct mascot poses', () {
    for (final entry in {
      'resolving': IsmePlaybackPose.finding,
      'loading': IsmePlaybackPose.connecting,
      'buffering': IsmePlaybackPose.buffering,
    }.entries) {
      expect(playbackPose(phase: 'Preparing media', nativeStatus: entry.key), entry.value);
    }
    expect(playbackPose(phase: 'Initializing player'), IsmePlaybackPose.starting);
    expect(playbackPose(phase: 'Validating stream'), IsmePlaybackPose.connecting);
    expect(playbackPose(phase: 'Buffering startup'), IsmePlaybackPose.buffering);
    expect(playbackPose(phase: 'Recovering playback'), IsmePlaybackPose.retrying);
    expect(playbackPose(phase: 'Preparing media', attempts: 2), IsmePlaybackPose.retrying);
    expect(playbackPose(phase: 'Stopped', failed: true), IsmePlaybackPose.failed);
    expect(playbackPose(phase: 'Initializing player', leaving: true), IsmePlaybackPose.closing);
  });

  testWidgets('every pose renders and disposes with reduced motion', (tester) async {
    for (final pose in IsmePlaybackPose.values) {
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(child: PlaybackMascot(pose: pose)),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('animated mascot can unmount without ticker leaks', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlaybackMascot(pose: IsmePlaybackPose.finding)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
