import 'package:flutter/material.dart';

import '../../core/key_presser.dart';
import '../theme.dart';
import 'remote_key.dart';

/// A vertical two-way key (volume, channel) with a legend in the middle.
class Rocker extends StatelessWidget {
  const Rocker({
    super.key,
    required this.upCode,
    required this.downCode,
    required this.upIcon,
    required this.downIcon,
    required this.legend,
    required this.upLabel,
    required this.downLabel,
  });

  final int upCode;
  final int downCode;
  final IconData upIcon;
  final IconData downIcon;
  final String legend;
  final String upLabel;
  final String downLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = RemoteScope.of(context).isConnected;
    Widget half(int code, IconData icon, String label, BorderRadius radius) => KeySurface(
      keyCode: code,
      mode: PressMode.repeat,
      semanticLabel: label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: 64,
        height: 62,
        decoration: BoxDecoration(
          color: pressed ? context.palette.keyPressed : Colors.transparent,
          borderRadius: radius,
        ),
        child: Icon(icon, color: context.palette.text.withValues(alpha: enabled ? 1 : 0.4)),
      ),
    );

    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: context.palette.key,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: context.palette.keyEdge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          half(upCode, upIcon, upLabel, const BorderRadius.vertical(top: Radius.circular(32))),
          Text(
            legend,
            style: TextStyle(color: context.palette.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          half(downCode, downIcon, downLabel, const BorderRadius.vertical(bottom: Radius.circular(32))),
        ],
      ),
    );
  }
}
