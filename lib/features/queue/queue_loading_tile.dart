import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/palette.dart';

// The single consolidated "Processing…" row shown at the top of the active
// queue tab while one or more scanned PDFs are being parsed. Replaces the old
// per-request spinner rows: "Processing…" + a count badge (how many parse
// requests are in flight) + a 4-quarter timer ring tracking the oldest request.
//
// Stateful because the timer ring advances over time: it runs its own 1s ticker
// while mounted so the ring repaints without rebuilding the whole shell.
class QueueLoadingTile extends StatefulWidget {
  const QueueLoadingTile({
    super.key,
    required this.count,
    required this.oldestStart,
  });

  // Number of parse requests currently in flight for this tab.
  final int count;
  // Start time of the oldest in-flight request; drives the timer ring (worst-
  // case wait). The widget is only rendered when count > 0, so this is non-null.
  final DateTime oldestStart;

  @override
  State<QueueLoadingTile> createState() => _QueueLoadingTileState();
}

class _QueueLoadingTileState extends State<QueueLoadingTile> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.oldestStart);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Processing…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          _CountBadge(count: widget.count),
          const SizedBox(width: 12),
          SizedBox(
            width: 24,
            height: 24,
            child: CustomPaint(painter: _QuarterTimerPainter(elapsed)),
          ),
        ],
      ),
    );
  }
}

// A small circle holding the in-flight request count.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppPalette.gridHeader,
        border: Border.all(color: AppPalette.ink, width: 1.4),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppPalette.ink,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
      ),
    );
  }
}

// Draws a ring split into four 90° quadrants, each representing 15 seconds of a
// one-minute window. Quadrants fill clockwise as time elapses, each in an
// escalating colour (green → amber → orange → red). Past 60s the ring holds
// full red — the request is taking unusually long.
class _QuarterTimerPainter extends CustomPainter {
  _QuarterTimerPainter(this.elapsed);

  final Duration elapsed;

  static const _quarterColors = [
    Color(0xFF1D7A3A), // 0–15s  green
    Color(0xFFF2C94C), // 15–30s amber
    Color(0xFFE08A1E), // 30–45s orange
    Color(0xFFD94F3A), // 45–60s red
  ];
  static const _trackColor = Color(0xFFD9D4C7);
  static const double _stroke = 3.2;
  // 90° per quarter; start at 12 o'clock and sweep clockwise.
  static const double _quarterSweep = math.pi / 2;
  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = _stroke / 2 + 0.5;
    final arcRect = rect.deflate(inset);

    final seconds = elapsed.inMilliseconds / 1000.0;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.butt
      ..color = _trackColor;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.butt;

    for (var q = 0; q < 4; q++) {
      final quarterStart = _startAngle + q * _quarterSweep;
      // Faint track behind every quadrant.
      canvas.drawArc(arcRect, quarterStart, _quarterSweep, false, track);
      // How far this quadrant has filled (its 15s window).
      final progress = ((seconds - q * 15) / 15).clamp(0.0, 1.0);
      if (progress > 0) {
        fill.color = _quarterColors[q];
        canvas.drawArc(
            arcRect, quarterStart, _quarterSweep * progress, false, fill);
      }
    }
  }

  @override
  bool shouldRepaint(_QuarterTimerPainter old) => old.elapsed != elapsed;
}
