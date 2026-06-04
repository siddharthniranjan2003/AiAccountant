import 'package:flutter/material.dart';
import '../../core/palette.dart';
import '../../core/models.dart';
import '../../core/utils.dart';
class QueueRowTile extends StatelessWidget {
  const QueueRowTile({
    super.key,
    required this.entry,
    required this.serialNumber,
    required this.isFirst,
    required this.onPartyTap,
  });

  final QueueEntry entry;
  final int serialNumber;
  final bool isFirst;
  final VoidCallback? onPartyTap;

  @override
  Widget build(BuildContext context) {
    final isDone = entry.status == QueueStatus.done;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.party,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isDone || entry.isBeingEdited ? AppPalette.muted : AppPalette.pen,
                              fontWeight: FontWeight.w800,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.underline,
                            ),
                      ),
                      Text(
                        entry.timeLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppPalette.inkSoft,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                formatCurrency(entry.amount),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (entry.type == TransactionType.purchase) ...[
                const SizedBox(width: 8),
                _SourceIcon(scanResult: entry.scanResult),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon({this.scanResult});
  final Map<String, dynamic>? scanResult;

  @override
  Widget build(BuildContext context) {
    final sourcePayload = scanResult?['__source_payload'] as Map<String, dynamic>?;
    final fetchedFrom = sourcePayload?['fetched_from'] as String?;
    final isEmail = fetchedFrom == 'email';

    return Icon(
      isEmail ? Icons.email_outlined : Icons.camera_alt_outlined,
      size: 16,
      color: AppPalette.muted,
    );
  }
}
