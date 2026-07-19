import 'package:flutter/material.dart';
import 'models.dart';

String sheetSlug(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

String formatCurrency(num amount) {
  final hasDecimals = amount != amount.roundToDouble();
  return '₹${_groupIndian(amount.toStringAsFixed(hasDecimals ? 2 : 0))}';
}

/// Adds Indian-system thousands separators to a plain decimal string
/// (e.g. "1905150.56" -> "19,05,150.56"): the last 3 integer digits are
/// grouped together, then the rest in pairs. Any fractional part is preserved.
String _groupIndian(String number) {
  final negative = number.startsWith('-');
  final s = negative ? number.substring(1) : number;
  final dot = s.indexOf('.');
  final intPart = dot == -1 ? s : s.substring(0, dot);
  final frac = dot == -1 ? '' : s.substring(dot);

  String grouped;
  if (intPart.length <= 3) {
    grouped = intPart;
  } else {
    final last3 = intPart.substring(intPart.length - 3);
    final head = intPart.substring(0, intPart.length - 3);
    final pairs = <String>[];
    for (var i = head.length; i > 0; i -= 2) {
      final start = i - 2 < 0 ? 0 : i - 2;
      pairs.insert(0, head.substring(start, i));
    }
    grouped = '${pairs.join(',')},$last3';
  }
  return '${negative ? '-' : ''}$grouped$frac';
}

/// Renders a date string as dd/mm/yyyy. Returns the original (or '—' when
/// empty) if it can't be parsed.
String formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final dd = parsed.day.toString().padLeft(2, '0');
  final mm = parsed.month.toString().padLeft(2, '0');
  return '$dd/$mm/${parsed.year}';
}

/// Indian-grouped decimal with exactly two places and no currency symbol
/// (e.g. 2011 -> "2,011.00"). Used for the RATE column and ₹-prefixed amounts
/// in the Stock Info history tables.
String formatDecimal(num n) => _groupIndian(n.toStringAsFixed(2));

/// Renders an ISO date (yyyy-mm-dd) as "29 May 26" (dd MMM yy). Returns '—'
/// when empty and the raw string when unparseable. No intl dependency.
String formatShortDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final dd = parsed.day.toString().padLeft(2, '0');
  final yy = (parsed.year % 100).toString().padLeft(2, '0');
  return '$dd ${months[parsed.month - 1]} $yy';
}

Color captureColorForType(TransactionType type, {int seedOffset = 0}) {
  final colors = type == TransactionType.sale
      ? const [
          Color(0xFFD94F3A),
          Color(0xFFF2C94C),
          Color(0xFFCA7C57),
        ]
      : const [
          Color(0xFF5B7AE5),
          Color(0xFF55A780),
          Color(0xFF7FA6F6),
        ];
  return colors[seedOffset % colors.length];
}
