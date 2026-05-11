import 'package:flutter/material.dart';
import 'models.dart';

String sheetSlug(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

String formatCurrency(num amount) {
  final hasDecimals = amount != amount.roundToDouble();
  return '₹${amount.toStringAsFixed(hasDecimals ? 2 : 0)}';
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
