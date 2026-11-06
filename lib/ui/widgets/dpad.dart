import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/key_presser.dart';
import '../../protocol/key_codes.dart';
import '../../protocol/remote_messages.dart';
import '../theme.dart';
import 'remote_key.dart';

enum _Zone { up, down, left, right, center }

/// The ring D-pad: one surface, zone picked from where the finger lands.
/// Arrows auto-repeat while held; OK supports long-press.
class DPad extends StatefulWidget {
  const DPad({super.key, this.size = 260});
  final double size;

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  KeyPresser? _presser;
  _Zone? _pressed;
  int? _pointer;

  static const _codes = {
    _Zone.up: Keys.dpadUp,
    _Zone.down: Keys.dpadDown,
    _Zone.left: Keys.dpadLeft,
    _Zone.right: Keys.dpadRight,
    _Zone.center: Keys.dpadCenter,
  };

  KeyPresser get _p => _presser ??= KeyPresser((c, d) => RemoteScope.read(context).sendKey(c, d));

  _Zone _zoneAt(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = local - c;
    if (v.distance < widget.size * 0.22) return _Zone.center;
    final a = math.atan2(v.dy, v.dx); // 0 = right, +π/2 = down
    if (a.abs() <= math.pi / 4) return _Zone.right;
    if (a.abs() >= 3 * math.pi / 4) return _Zone.left;
    return a > 0 ? _Zone.down : _Zone.up;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    final v = e.localPosition - Offset(widget.size / 2, widget.size / 2);
    if (v.distance > widget.size / 2) return; // outside the ring
    _pointer = e.pointer;
    final zone = _zoneAt(e.localPosition);
    HapticFeedback.selectionClick();
    setState(() => _pressed = zone);
    _p.down(_codes[zone]!, zone == _Zone.center ? PressMode.normal : PressMode.repeat);
  }

  void _up(PointerEvent e, {bool cancel = false}) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    setState(() => _pressed = null);
    cancel ? _p.cancel() : _p.up();
  }

  @override
  void dispose() {
    _presser?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = RemoteScope.of(context).isConnected;
    final s = widget.size;
    Widget chevron(IconData icon, Alignment at) => Align(
      alignment: at,
      child: Padding(
        padding: EdgeInsets.all(s * 0.06),
        child: Icon(icon, size: 34, color: context.palette.text.withValues(alpha: enabled ? 0.9 : 0.35)),
      ),
    );

    return Semantics(
      label: 'Direction pad',
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: (e) => _up(e, cancel: true),
        child: SizedBox(
          width: s,
          height: s,
          child: CustomPaint(
            painter: _RingPainter(pressed: _pressed, p: context.palette),
            child: Stack(
              children: [
                chevron(Icons.keyboard_arrow_up_rounded, Alignment.topCenter),
                chevron(Icons.keyboard_arrow_down_rounded, Alignment.bottomCenter),
                chevron(Icons.keyboard_arrow_left_rounded, Alignment.centerLeft),
                chevron(Icons.keyboard_arrow_right_rounded, Alignment.centerRight),
                Center(
                  child: Text(
                    'OK',
                    style: TextStyle(
                      color: context.palette.text.withValues(alpha: enabled ? 1 : 0.35),
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.pressed, required this.p});
  final _Zone? pressed;
  final RemotePalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final inner = size.width * 0.22;

    canvas.drawCircle(c, r, Paint()..color = p.key);
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = p.keyEdge,
    );

    if (pressed != null && pressed != _Zone.center) {
      final start = switch (pressed!) {
        _Zone.right => -math.pi / 4,
        _Zone.down => math.pi / 4,
        _Zone.left => 3 * math.pi / 4,
        _ => -3 * math.pi / 4,
      };
      final band = (r - inner) * 0.5;
      final arcRadius = r - band / 2 - 4;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: arcRadius),
        start + 0.08,
        math.pi / 2 - 0.16,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = band
          ..strokeCap = StrokeCap.round
          ..color = p.led.withValues(alpha: 0.22),
      );
      // The "LED" edge: a thin bright arc on the rim.
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 3),
        start + 0.12,
        math.pi / 2 - 0.24,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = p.led,
      );
    }

    final centerPressed = pressed == _Zone.center;
    canvas.drawCircle(c, inner, Paint()..color = centerPressed ? p.keyPressed : p.okKey);
    canvas.drawCircle(
      c,
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = centerPressed ? 2.5 : 1
        ..color = centerPressed ? p.led : p.keyEdge,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pressed != pressed || old.p != p;
}

/// Swipe surface: each ~36 px of travel along the dominant axis is one arrow
/// press, tap is OK, long-press is a long OK.
class Touchpad extends StatefulWidget {
  const Touchpad({super.key, this.size = 260});
  final double size;

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<Touchpad> {
  static const _step = 36.0;
  Offset _acc = Offset.zero;
  bool _active = false;

  // Gestures are read from raw pointer events: an eager recognizer claims
  // every touch on the pad so the enclosing scroll view can't steal vertical
  // swipes, which also means GestureDetector's tap/long-press/pan would lose.
  int? _pointer;
  Offset _start = Offset.zero;
  bool _moved = false;
  bool _longActive = false;
  Timer? _longTimer;

  void _send(int code, [KeyDirection d = KeyDirection.short]) {
    HapticFeedback.selectionClick();
    RemoteScope.read(context).sendKey(code, d);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _start = e.position;
    _acc = Offset.zero;
    _moved = false;
    _longActive = false;
    _longTimer = Timer(kLongPressTimeout, () {
      _longActive = true;
      _send(Keys.dpadCenter, KeyDirection.startLong);
    });
    setState(() => _active = true);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (!_moved && (e.position - _start).distance > kTouchSlop) {
      _moved = true;
      if (!_longActive) _longTimer?.cancel();
    }
    if (!_longActive) _feed(e.delta);
  }

  void _end(PointerEvent e, {bool cancel = false}) {
    if (e.pointer != _pointer) return;
    _longTimer?.cancel();
    if (_longActive) {
      _send(Keys.dpadCenter, KeyDirection.endLong);
    } else if (!cancel && !_moved) {
      _send(Keys.dpadCenter);
    }
    _pointer = null;
    _longActive = false;
    setState(() => _active = false);
  }

  @override
  void dispose() {
    _longTimer?.cancel();
    super.dispose();
  }

  void _feed(Offset delta) {
    _acc += delta;
    while (_acc.dx.abs() >= _step || _acc.dy.abs() >= _step) {
      if (_acc.dx.abs() >= _acc.dy.abs()) {
        final right = _acc.dx > 0;
        _send(right ? Keys.dpadRight : Keys.dpadLeft);
        _acc = Offset(_acc.dx - (right ? _step : -_step), 0);
      } else {
        final down = _acc.dy > 0;
        _send(down ? Keys.dpadDown : Keys.dpadUp);
        _acc = Offset(0, _acc.dy - (down ? _step : -_step));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = RemoteScope.of(context).isConnected;
    return Semantics(
      label: 'Touchpad. Swipe to move, tap to select.',
      child: RawGestureDetector(
        gestures: {
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
        },
        child: Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _end,
          onPointerCancel: (e) => _end(e, cancel: true),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: context.palette.key,
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: _active ? context.palette.led : context.palette.keyEdge,
                width: _active ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'Swipe to move\nTap to select',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.muted.withValues(alpha: enabled ? 1 : 0.4)),
            ),
          ),
        ),
      ),
    );
  }
}
