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
    // One scan sweeps over a minute; two or more in flight stretch the ring to
    // 90s to better reflect the longer worst-case wait.
    final fullMs = widget.count >= 2 ? 90000 : 60000;
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
            child: CustomPaint(
              painter: _StepTimerPainter(elapsed, fullMs),
            ),
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
// the circle over [fullMs] (60s for one scan, 90s for two or more), changing colour
// in four equal steps green → amber → orange → red. The unfilled part is a faint
// track. Once the wedge completes it restarts from empty and sweeps again, looping
// until the scan finishes (this tile is only shown while a scan is in flight).
class _StepTimerPainter extends CustomPainter {
  _StepTimerPainter(this.elapsed, this.fullMs);

  final Duration elapsed;
  final int fullMs; // full sweep duration; the ring loops every fullMs

  static const _stepColors = [
    Color(0xFF1D7A3A), // step 1  green
    Color(0xFFF2C94C), // step 2  amber
    Color(0xFFE08A1E), // step 3  orange
    Color(0xFFD94F3A), // step 4  red
  ];
  static const _trackColor = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final windowMs = fullMs ~/ _stepColors.length; // one colour step
    // Loop the sweep: restart from empty each time the wedge completes a circle.
    final cycleMs = elapsed.inMilliseconds % fullMs;
    final step = (cycleMs ~/ windowMs).clamp(0, _stepColors.length - 1);
    // Fraction of the current sweep elapsed → how much of the pie is filled.
    final progress = (cycleMs / fullMs).clamp(0.0, 1.0);

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
  bool shouldRepaint(_StepTimerPainter old) =>
      old.elapsed != elapsed || old.fullMs != fullMs;
}
