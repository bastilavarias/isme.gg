import 'package:flutter_test/flutter_test.dart';
import 'package:ismegg/playback_recovery.dart';

void main() {
  test('transient failure retries once, then advances and stops at budget', () {
    final budget = RecoveryBudget()..record(0);
    int? next() => budget.next(current: 0, fault: PlaybackFault.transient,
        candidates: [0, 1, 2], manualSource: false);
    expect(next(), 0);
    budget.record(0);
    expect(next(), 1);
    budget.record(1);
    expect(budget.next(current: 1, fault: PlaybackFault.transient,
        candidates: [0, 1, 2], manualSource: false), isNull);
    budget.reset();
    expect(budget.total, 0);
  });

  test('incompatible source skips used sources without retrying it', () {
    final budget = RecoveryBudget()..record(1);
    expect(budget.next(current: 1, fault: PlaybackFault.incompatible,
        candidates: [1, 4, 7], manualSource: false), 4);
  });

  test('internal faults stop and manually supplied sources never switch', () {
    final budget = RecoveryBudget()..record(0);
    expect(budget.next(current: 0, fault: PlaybackFault.internal,
        candidates: [0, 1], manualSource: false), isNull);
    expect(budget.next(current: 0, fault: PlaybackFault.incompatible,
        candidates: [0, 1], manualSource: true), isNull);
    expect(budget.next(current: 0, fault: PlaybackFault.transient,
        candidates: [0, 1], manualSource: true), 0);
  });

  test('diagnostic reasons retain known failures without leaking raw data', () {
    expect(safePlaybackDetail('Bad state: Video exceeds 3 GiB device cache limit'),
      'video exceeds 3 gib device cache limit');
    expect(safePlaybackDetail('Not enough free device storage for playback'),
      'not enough free device storage for playback');
    expect(safePlaybackDetail('HTTP 403 https://example.com/private?token=secret'),'HTTP 403');
    expect(safePlaybackDetail('unknown https://example.com/private?token=secret'),
      'Unrecognized error (details withheld)');
  });
  test('classifies known errors without guessing unknown causes', () {
    expect(classifyPlaybackError('HTTP 403'), PlaybackFault.internal);
    expect(classifyPlaybackError('Not enough free device storage for playback'), PlaybackFault.internal);
    expect(classifyPlaybackError('unsupported decoder'), PlaybackFault.incompatible);
    expect(classifyPlaybackError('Media range response truncated'), PlaybackFault.transient);
    expect(classifyPlaybackError('Source error'), PlaybackFault.unknown);
  });
}
