import 'dart:async';

import '../protocol/remote_messages.dart';

enum PressMode {
  /// Tap → SHORT; hold → START_LONG … END_LONG (context menus, Home dashboard).
  normal,

  /// SHORT on touch-down, then auto-repeat while held (arrows, volume, channel).
  repeat,
}

/// Turns finger down/up into protocol key events with physical-remote timing.
class KeyPresser {
  KeyPresser(
    this._send, {
    this.longPressAfter = const Duration(milliseconds: 400),
    this.repeatEvery = const Duration(milliseconds: 100),
  });

  final void Function(int keyCode, KeyDirection direction) _send;
  final Duration longPressAfter;
  final Duration repeatEvery;

  int? _code;
  PressMode _mode = PressMode.normal;
  bool _longActive = false;
  Timer? _timer;

  void down(int keyCode, PressMode mode) {
    if (_code != null) up();
    _code = keyCode;
    _mode = mode;
    _longActive = false;
    if (mode == PressMode.repeat) {
      _send(keyCode, KeyDirection.short);
      _timer = Timer(longPressAfter, () {
        _send(keyCode, KeyDirection.short);
        _timer = Timer.periodic(repeatEvery, (_) => _send(keyCode, KeyDirection.short));
      });
    } else {
      _timer = Timer(longPressAfter, () {
        _longActive = true;
        _send(keyCode, KeyDirection.startLong);
      });
    }
  }

  void up() => _release(sendTap: true);

  /// Finger slid off / gesture cancelled: never sends a tap, but always closes a long press.
  void cancel() => _release(sendTap: false);

  void _release({required bool sendTap}) {
    final code = _code;
    if (code == null) return;
    _timer?.cancel();
    _timer = null;
    if (_mode == PressMode.normal) {
      if (_longActive) {
        _send(code, KeyDirection.endLong);
      } else if (sendTap) {
        _send(code, KeyDirection.short);
      }
    }
    _code = null;
    _longActive = false;
  }

  void dispose() => cancel();
}
