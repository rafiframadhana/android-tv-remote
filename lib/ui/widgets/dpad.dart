import 'dart:math' as math;

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
        child: Icon(icon, size: 34, color: RemoteColors.text.withValues(alpha: enabled ? 0.9 : 0.35)),
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
            painter: _RingPainter(pressed: _pressed),
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
                      color: RemoteColors.text.withValues(alpha: enabled ? 1 : 0.35),
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
  _RingPainter({required this.pressed});
  final _Zone? pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final inner = size.width * 0.22;

    canvas.drawCircle(c, r, Paint()..color = RemoteColors.key);
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = RemoteColors.keyEdge,
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
          ..color = RemoteColors.led.withValues(alpha: 0.22),
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
          ..color = RemoteColors.led,
      );
    }

    final centerPressed = pressed == _Zone.center;
    canvas.drawCircle(c, inner, Paint()..color = centerPressed ? RemoteColors.keyPressed : const Color(0xFF2F384E));
    canvas.drawCircle(
      c,
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = centerPressed ? 2.5 : 1
        ..color = centerPressed ? RemoteColors.led : RemoteColors.keyEdge,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pressed != pressed;
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

  void _send(int code, [KeyDirection d = KeyDirection.short]) {
    HapticFeedback.selectionClick();
    RemoteScope.read(context).sendKey(code, d);
  }

  void _onPan(DragUpdateDetails d) {
    _acc += d.delta;
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
      child: GestureDetector(
        onTap: () => _send(Keys.dpadCenter),
        onLongPressStart: (_) => _send(Keys.dpadCenter, KeyDirection.startLong),
        onLongPressEnd: (_) => _send(Keys.dpadCenter, KeyDirection.endLong),
        onPanStart: (_) => setState(() {
          _acc = Offset.zero;
          _active = true;
        }),
        onPanUpdate: _onPan,
        onPanEnd: (_) => setState(() => _active = false),
        onPanCancel: () => setState(() => _active = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: RemoteColors.key,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: _active ? RemoteColors.led : RemoteColors.keyEdge, width: _active ? 2 : 1),
          ),
          alignment: Alignment.center,
          child: Text(
            'Swipe to move\nTap to select',
            textAlign: TextAlign.center,
            style: TextStyle(color: RemoteColors.muted.withValues(alpha: enabled ? 1 : 0.4)),
          ),
        ),
      ),
    );
  }
}
