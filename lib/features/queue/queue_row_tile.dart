import 'package:flutter/material.dart';
import '../../core/palette.dart';
import '../../core/models.dart';
import '../../core/utils.dart';
import '../../shared/ink_checkbox.dart';

class QueueRowTile extends StatelessWidget {
  const QueueRowTile({
    super.key,
    required this.entry,
    required this.serialNumber,
    required this.isFirst,
    required this.onPartyTap,
    required this.onCheckboxTap,
  });

  final QueueEntry entry;
  final int serialNumber;
  final bool isFirst;
  final VoidCallback? onPartyTap;
  final VoidCallback? onCheckboxTap;

  @override
  Widget build(BuildContext context) {
    final isDone = entry.status == QueueStatus.done;
    final isProcessing = entry.status == QueueStatus.processing;
    final opacity = entry.status == QueueStatus.pending ? 1.0 : 0.56;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: isFirst
                ? BorderSide.none
                : BorderSide(color: AppPalette.line.withValues(alpha: 0.8), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$serialNumber',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onPartyTap,
                  child: Text(
                    entry.party,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDone ? AppPalette.muted : AppPalette.pen,
                          fontWeight: FontWeight.w800,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : TextDecoration.underline,
                        ),
                  ),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  formatCurrency(entry.amount),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Text(
                  entry.timeLabel,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 22,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkCheckbox(
                    value: entry.checked,
                    success: isDone,
                    processing: isProcessing,
                    onTap: onCheckboxTap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
