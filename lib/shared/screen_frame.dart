import 'package:flutter/material.dart';
import '../core/palette.dart';
import 'app_bottom_nav.dart';

class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
    required this.body,
    this.stickyFooter,
    this.overlays = const <Widget>[],
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;
  final Widget body;
  final Widget? stickyFooter;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF9ED),
              Color(0xFFF1E7D3),
              AppPalette.paper,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.sheet,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: AppPalette.ink, width: 1.8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A141E3C),
                        offset: Offset(4, 6),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _PaperPainter(),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            Expanded(child: body),
                            ?stickyFooter,
                            AppBottomNav(
                              currentIndex: currentIndex,
                              onSelected: onNavSelected,
                            ),
                          ],
                        ),
                        ...overlays,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppPalette.line.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (double y = 24; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
