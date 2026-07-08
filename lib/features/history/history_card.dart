import 'package:flutter/material.dart';
import '../../core/palette.dart';
import '../../core/models.dart';
import '../../core/utils.dart';

class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.entry,
    this.onTap,
  });

  final HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSale = entry.type == TransactionType.sale;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppPalette.cardBorder, width: AppPalette.cardBorderWidth),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppPalette.cardBorder, width: 1.3),
                color: isSale
                    ? AppPalette.accent2.withValues(alpha: 0.35)
                    // The blue-grey badge fill predates the web palette split
                    // (it was AppPalette.line); keep it fixed on both.
                    : const Color(0xFFB9C8DF).withValues(alpha: 0.35),
              ),
              child: Text(
                isSale ? 'S' : 'P',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.party,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.type.label} · ${entry.dateLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '${isSale ? '+' : '−'}${formatCurrency(entry.amount)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSale ? AppPalette.success : AppPalette.accent,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
