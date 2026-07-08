import 'package:flutter/material.dart';
import '../core/constants.dart';

extension ResponsiveContext on BuildContext {
  /// True on desktop-sized viewports — the same breakpoint the shell uses to
  /// switch from the phone card + bottom nav to the side-rail layout.
  bool get isWideScreen =>
      MediaQuery.sizeOf(this).width >= kDesktopBreakpoint;
}

/// Centers [child] and caps its width on wide (desktop) screens so forms don't
/// stretch edge-to-edge. On narrow screens [child] is returned unchanged.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!context.isWideScreen) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
