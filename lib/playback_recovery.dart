/// Bounded recovery policy. No network/provider discovery is performed here.
enum PlaybackFault { transient, incompatible, internal, unknown }

class PlaybackFailure implements Exception {
  final PlaybackFault kind;
  final String message;
  const PlaybackFailure(this.kind, this.message);
  @override
  String toString() => message;
}

PlaybackFault classifyPlaybackError(Object error) {
  if (error is PlaybackFailure) return error.kind;
  final text = error.toString().toLowerCase();
  if (text.contains('403') || text.contains('416') || text.contains('410') ||
      text.contains('invalid playback origin') || text.contains('cleartext') ||
      text.contains('permission denied') || text.contains('unsafe torrent') ||
      text.contains('no space left') || text.contains('cache limit')) {
    return PlaybackFault.internal;
  }
  if (text.contains('decoder') || text.contains('unsupported') ||
      text.contains('unrecognizedinputformat') || text.contains('no playable video')) {
    return PlaybackFault.incompatible;
  }
  if (text.contains('timeout') || text.contains('timed out') ||
      text.contains('deadline') || text.contains('socket') ||
      text.contains('connection') || text.contains('buffer') ||
      text.contains('truncated') || text.contains('409') || text.contains('503')) {
    return PlaybackFault.transient;
  }
  // "Source error" alone does not identify the root cause.
  return PlaybackFault.unknown;
}

class RecoveryBudget {
  static const maxAttempts = 3;
  final Map<int, int> _attempts = {};
  int total = 0;
  void reset() { _attempts.clear(); total = 0; }
  void record(int index) {
    total++;
    _attempts[index] = (_attempts[index] ?? 0) + 1;
  }
  int? next({required int current, required PlaybackFault fault,
      required Iterable<int> candidates, required bool manualSource}) {
    if (total >= maxAttempts || fault == PlaybackFault.internal) return null;
    if (fault == PlaybackFault.transient && (_attempts[current] ?? 0) < 2) {
      return current;
    }
    if (manualSource) return null;
    for (final candidate in candidates) {
      if (candidate >= 0 && !_attempts.containsKey(candidate)) return candidate;
    }
    return null;
  }
}
