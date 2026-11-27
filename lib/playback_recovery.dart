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
      text.contains('no space left') || text.contains('cache limit') ||
      text.contains('not enough free device storage')) {
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

/// Keep known diagnostic reasons, not arbitrary exception strings (which may
/// include credentials, paths, media titles, hashes or provider endpoints).
String safePlaybackDetail(Object error) {
  final text=error.toString().toLowerCase();
  const reasons=[
    'video exceeds 7 gib device cache limit',
    'video exceeds 3 gib device cache limit',
    'not enough free device storage for playback',
    'no space left', 'unsafe torrent file path',
    'episode file index unavailable', 'episode file could not be identified unambiguously',
    'no playable video file found', 'no matching torrent sources found',
    'source index unavailable', 'this title has no supported media id',
    'could not create private cache', 'invalid magnet uri',
    'media readiness deadline exceeded', 'media data deadline exceeded',
    'torrent data is missing on disk', 'invalid media endpoint',
    'invalid playback origin', 'media range response invalid',
    'media range response truncated', 'media range response too long',
    'playback stalled', 'permission denied', 'cleartext',
    'unsupported decoder', 'unrecognizedinputformat', 'source error',
    'decoder', 'timeout', 'timed out', 'connection', 'socket',
  ];
  for(final reason in reasons){
    if(text.contains(reason))return reason;
  }
  final http=RegExp(r'\bhttp\s+([1-5]\d\d)\b').firstMatch(text);
  if(http!=null)return 'HTTP ${http.group(1)}';
  return 'Unrecognized error (details withheld)';
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
