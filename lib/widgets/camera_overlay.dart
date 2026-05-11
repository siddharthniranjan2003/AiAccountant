import 'package:flutter/material.dart';

class CameraOverlayBrackets extends StatelessWidget {
  const CameraOverlayBrackets({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        CameraCorner(top: 72, left: 28),
        CameraCorner(top: 72, right: 28, rightSide: true),
        CameraCorner(bottom: 132, left: 28, bottomSide: true),
        CameraCorner(
          bottom: 132,
          right: 28,
          rightSide: true,
          bottomSide: true,
        ),
      ],
    );
  }
}

class CameraCorner extends StatelessWidget {
  const CameraCorner({
    super.key,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.rightSide = false,
    this.bottomSide = false,
  });

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final bool rightSide;
  final bool bottomSide;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: SizedBox(
        width: 26,
        height: 26,
        child: CustomPaint(
          painter: _CornerPainter(
            rightSide: rightSide,
            bottomSide: bottomSide,
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.rightSide,
    required this.bottomSide,
  });

  final bool rightSide;
  final bool bottomSide;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final horizontalStart =
        Offset(rightSide ? size.width : 0, bottomSide ? size.height : 0);
    final horizontalEnd = Offset(
        rightSide ? size.width - 18 : 18, bottomSide ? size.height : 0);
    final verticalStart =
        Offset(rightSide ? size.width : 0, bottomSide ? size.height : 0);
    final verticalEnd = Offset(
        rightSide ? size.width : 0, bottomSide ? size.height - 18 : 18);

    canvas.drawLine(horizontalStart, horizontalEnd, paint);
    canvas.drawLine(verticalStart, verticalEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) {
    return oldDelegate.rightSide != rightSide ||
        oldDelegate.bottomSide != bottomSide;
  }
}
