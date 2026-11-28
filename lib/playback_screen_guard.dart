import 'dart:async';

/// Renews the Android screen-on lease during intended foreground playback.
/// Native expiry also releases a lease if the Dart isolate or channel fails.
class PlaybackScreenGuard {
  PlaybackScreenGuard(this._send, {required this.onFailure});

  final Future<bool> Function(bool active) _send;
  final void Function() onFailure;
  static const interval = Duration(seconds: 10);
  Timer? _timer;
  bool _active = false;
  bool _disposed = false;

  void update(bool active) {
    if (_disposed || active == _active) return;
    _active = active;
    _timer?.cancel();
    _timer = active ? Timer.periodic(interval, (_) => _request(true)) : null;
    unawaited(_request(active));
  }

  Future<void> _request(bool active) async {
    try {
      final actual = await _send(active).timeout(const Duration(seconds: 5));
      if (!_disposed && _active == active && actual != active) onFailure();
    } catch (_) {
      if (!_disposed && _active == active) onFailure();
    }
  }

  void dispose() {
    if (_disposed) return;
    update(false);
    _disposed = true;
  }
}
