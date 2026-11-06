import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/key_presser.dart';
import '../../core/tv_connection.dart';
import '../theme.dart';

/// Makes the current [TvConnection] available to keys below it.
class RemoteScope extends InheritedNotifier<TvConnection> {
  const RemoteScope({super.key, required TvConnection connection, required super.child}) : super(notifier: connection);

  static TvConnection of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RemoteScope>()!.notifier!;

  static TvConnection read(BuildContext context) => context.getInheritedWidgetOfExactType<RemoteScope>()!.notifier!;
}

/// Low-level press surface: reacts on finger-down (no tap delay), forwards
/// down/up to a [KeyPresser], and shows a pressed state with a haptic tick.
class KeySurface extends StatefulWidget {
  const KeySurface({
    super.key,
    required this.keyCode,
    required this.builder,
    this.mode = PressMode.normal,
    this.semanticLabel,
  });

  final int keyCode;
  final PressMode mode;
  final String? semanticLabel;
  final Widget Function(BuildContext context, bool pressed) builder;

  @override
  State<KeySurface> createState() => _KeySurfaceState();
}

class _KeySurfaceState extends State<KeySurface> {
  KeyPresser? _presser;
  bool _pressed = false;

  KeyPresser _ensurePresser() => _presser ??= KeyPresser((code, dir) => RemoteScope.read(context).sendKey(code, dir));

  void _down() {
    HapticFeedback.selectionClick();
    setState(() => _pressed = true);
    _ensurePresser().down(widget.keyCode, widget.mode);
  }

  void _up({bool cancel = false}) {
    if (!_pressed) return;
    setState(() => _pressed = false);
    cancel ? _presser?.cancel() : _presser?.up();
  }

  @override
  void dispose() {
    _presser?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: () {
        final p = _ensurePresser();
        p.down(widget.keyCode, PressMode.normal);
        p.up();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(cancel: true),
        child: widget.builder(context, _pressed),
      ),
    );
  }
}

/// A rounded rubber key with an icon or a short label.
class RemoteKey extends StatelessWidget {
  const RemoteKey({
    super.key,
    required this.keyCode,
    required this.label,
    this.icon,
    this.text,
    this.mode = PressMode.normal,
    this.width = 64,
    this.height = 56,
    this.color,
    this.circle = false,
  });

  final int keyCode;
  final String label;
  final IconData? icon;
  final String? text;
  final PressMode mode;
  final double width;
  final double height;
  final Color? color;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final enabled = RemoteScope.of(context).isConnected;
    final fg = color ?? context.palette.text;
    return KeySurface(
      keyCode: keyCode,
      mode: mode,
      semanticLabel: label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed ? context.palette.keyPressed : context.palette.key,
          borderRadius: circle ? null : BorderRadius.circular(height / 2.6),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          border: Border.all(
            color: pressed ? context.palette.led.withValues(alpha: 0.7) : context.palette.keyEdge,
            width: 1,
          ),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: icon != null
              ? Icon(icon, color: fg, size: 24)
              : Text(
                  text ?? label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15),
                ),
        ),
      ),
    );
  }
}
