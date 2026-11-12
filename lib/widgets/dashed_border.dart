import 'package:flutter/material.dart';

import '../theme.dart';

/// A rounded box with a dashed outline around [child], optionally filled: the "add" boxes of the
/// vehicle screens ("Add another vehicle", "Add photos").
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.child,
    this.color = carShareGreen,
    this.radius = carShareCardRadius,
    this.fill,
  });

  final Widget child;
  final Color color;
  final double radius;

  /// Background inside the outline; none by default.
  final Color? fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorderPainter(color: color, radius: radius),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    ),
  );
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 7), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
