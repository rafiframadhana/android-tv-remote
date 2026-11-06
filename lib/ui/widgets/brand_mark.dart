import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The TV Remote logo: a ring D-pad whose right key is pressed (lit), around the OK key.
/// Same geometry as design/logo/build_logo.py (256-unit canvas).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'TV Remote',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: _BrandMarkPainter()),
  );
}

class _BrandMarkPainter extends CustomPainter {
  static const _rIn = 58.0, _rOut = 104.0, _gap = 11.0, _dot = 34.0, _c = 128.0;

  /// Annular segment centred on [midDeg] spanning ±[half]°, with straight cuts of constant width [_gap].
  Path _segment(double midDeg, double half) {
    Offset cut(double diagDeg, double r, double side) {
      final th = diagDeg * math.pi / 180;
      final u = Offset(math.cos(th), math.sin(th));
      final n = Offset(-math.sin(th), math.cos(th));
      final h = _gap / 2 * side;
      final t = math.sqrt(r * r - h * h);
      return const Offset(_c, _c) + u * t + n * h;
    }

    final a0 = midDeg - half, a1 = midDeg + half;
    final large = 2 * half > 180;
    final o0 = cut(a0, _rOut, 1), o1 = cut(a1, _rOut, -1);
    final i1 = cut(a1, _rIn, -1), i0 = cut(a0, _rIn, 1);
    return Path()
      ..moveTo(o0.dx, o0.dy)
      ..arcToPoint(o1, radius: const Radius.circular(_rOut), largeArc: large)
      ..lineTo(i1.dx, i1.dy)
      ..arcToPoint(i0, radius: const Radius.circular(_rIn), largeArc: large, clockwise: false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 256);
    canvas.drawPath(_segment(180, 135), Paint()..color = RemoteColors.text);
    canvas.drawPath(_segment(0, 45), Paint()..color = RemoteColors.led);
    canvas.drawCircle(const Offset(_c, _c), _dot, Paint()..color = RemoteColors.text);
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => false;
}
