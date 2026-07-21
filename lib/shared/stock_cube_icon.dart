import 'package:flutter/material.dart';

/// The Stock Info cube glyph from the Option C mockups — a stroked 3D box
/// (24×24 viewBox: hexagonal outline + Y-shaped face lines), drawn with a
/// CustomPainter so it matches the design's SVG exactly.
class StockCubeIcon extends StatelessWidget {
  const StockCubeIcon({
    super.key,
    this.size = 17,
    required this.color,
    this.strokeWidth = 1.7,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CubePainter(color: color, strokeWidth: strokeWidth),
    );
  }
}

class _CubePainter extends CustomPainter {
  const _CubePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Cube outline (hexagon): top → right edge → bottom → left edge.
    final outline = Path()
      ..moveTo(12 * s, 2.9 * s)
      ..lineTo(21 * s, 8.2 * s)
      ..lineTo(21 * s, 15.8 * s)
      ..lineTo(12 * s, 21.1 * s)
      ..lineTo(3 * s, 15.8 * s)
      ..lineTo(3 * s, 8.2 * s)
      ..close();

    // Face edges: the Y — left rim → center, right rim → center, center → bottom.
    final faces = Path()
      ..moveTo(3.3 * s, 7.4 * s)
      ..lineTo(12 * s, 11.8 * s)
      ..lineTo(20.7 * s, 7.4 * s)
      ..moveTo(12 * s, 11.8 * s)
      ..lineTo(12 * s, 21 * s);

    canvas.drawPath(outline, paint);
    canvas.drawPath(faces, paint);
  }

  @override
  bool shouldRepaint(covariant _CubePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
