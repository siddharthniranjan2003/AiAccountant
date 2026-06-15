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
            child: CustomPaint(painter: _StepTimerPainter(elapsed)),
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

// A clock-style filled pie. A solid wedge sweeps clockwise from 12 o'clock, filling
// the circle over one minute, and the WHOLE wedge changes colour at each 15-second
// mark: 0–15s green, 15–30s amber, 30–45s orange, 45s+ red. The unfilled part is a
// faint track. Past 60s it holds a full red circle.
class _StepTimerPainter extends CustomPainter {
  _StepTimerPainter(this.elapsed);

  final Duration elapsed;

  static const _stepColors = [
    Color(0xFF1D7A3A), // 0–15s  green
    Color(0xFFF2C94C), // 15–30s amber
    Color(0xFFE08A1E), // 30–45s orange
    Color(0xFFD94F3A), // 45s+   red
  ];
  static const _trackColor = Colors.white;
  static const int _windowMs = 15000; // one colour step
  static const int _fullMs = _windowMs * 4; // 60s = full circle

  @override
  void paint(Canvas canvas, Size size) {
    final totalMs = elapsed.inMilliseconds;
    final step = (totalMs ~/ _windowMs).clamp(0, _stepColors.length - 1);
    // Fraction of the full minute elapsed → how much of the pie is filled.
    final progress = (totalMs / _fullMs).clamp(0.0, 1.0);

    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Faint track behind the un-elapsed portion.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = _trackColor,
    );
    // Coloured wedge sweeping clockwise from 12 o'clock.
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        true, // useCenter → a pie slice, not an arc stroke
        Paint()
          ..style = PaintingStyle.fill
          ..color = _stepColors[step],
      );
    }
    // Thin border for crisp definition, matching the count badge.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppPalette.ink,
    );
  }

  @override
  bool shouldRepaint(_StepTimerPainter old) => old.elapsed != elapsed;
}
