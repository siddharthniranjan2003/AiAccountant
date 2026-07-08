import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// On web the app uses the "Option C" accounting look: cool light-grey canvas,
// solid white surfaces, hairline borders and the Manrope font (see theme.dart).
// Mobile keeps the original cream "paper" notebook look until it gets its own
// redesign, so only the surface/background tokens below are web-conditional —
// semantic colors (pen/accent/success…) are shared.
class AppPalette {
  static final paper =
      kIsWeb ? const Color(0xFFF1F3F6) : const Color(0xFFF6F1E6);
  static final sheet =
      kIsWeb ? const Color(0xFFFFFFFF) : const Color(0xFFFDF9F0);
  static const ink = Color(0xFF16181D);
  static const inkSoft = Color(0xFF3A3F49);
  static const pen = Color(0xFF1F3A8A);
  static const accent = Color(0xFFD94F3A);
  static const accent2 = Color(0xFFF2C94C);
  static final muted =
      kIsWeb ? const Color(0xFF888D96) : const Color(0xFF8A8576);
  static final line =
      kIsWeb ? const Color(0xFFE2E6EC) : const Color(0xFFB9C8DF);
  static const success = Color(0xFF1D7A3A);
  static final gridHeader =
      kIsWeb ? const Color(0xFFE9EDF2) : const Color(0xFFE9EEF5);

  // Cards (history/profile/export) draw a heavy ink "sketch" outline on
  // mobile; on web that reads as notebook, so they use a hairline instead.
  static final cardBorder = kIsWeb ? line : ink;
  static final double cardBorderWidth = kIsWeb ? 1.0 : 1.4;
  static final Color card =
      kIsWeb ? Colors.white : Colors.white.withValues(alpha: 0.65);

  const AppPalette._();
}
