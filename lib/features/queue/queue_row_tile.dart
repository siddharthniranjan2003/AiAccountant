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
    this.isQueueDuplicate = false,
    this.isAlreadyPushed = false,
  });

  final QueueEntry entry;
  final int serialNumber;
  final bool isFirst;
  final VoidCallback? onPartyTap;
  // True when this purchase's invoice number already appeared on an older queue
  // row (the same invoice uploaded again). Distinct from `invoiceExists`, which
  // means the voucher is already in TallyPrime.
  final bool isQueueDuplicate;
  // True when this purchase's invoice number already exists among pushed
  // vouchers (History) — the original has reached Tally. Takes label precedence
  // over isQueueDuplicate/invoiceExists.
  final bool isAlreadyPushed;

  @override
  Widget build(BuildContext context) {
    // The real lifecycle lives in the Supabase status string (carried on the
    // row as __status); the row reflects that, not a local enum.
    final status = entry.scanResult?['__status'] as String? ?? 'pending';
    final isPushed = status == 'pushed';
    final isFailed = status == 'failed';
    final isPushing = status == 'push_now';
    final isDuplicate = entry.invoiceExists;
    final isUnderEdit = entry.editState == QueueEditState.underEdit;
    // A saved edit reads as a normal, ready row (just tagged); only an unsaved
    // mid-edit row is dimmed.
    final opacity =
        (status == 'pending' && !isUnderEdit && !isDuplicate && !isQueueDuplicate && !isAlreadyPushed)
            ? 1.0
            : 0.56;

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
                              color: isFailed
                                  ? AppPalette.accent
                                  : (isPushed || isUnderEdit
                                      ? AppPalette.muted
                                      : AppPalette.pen),
                              fontWeight: FontWeight.w800,
                              decoration: isPushed
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.underline,
                            ),
                      ),
                      if (entry.invoiceNumber != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.invoiceNumber!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppPalette.muted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                      Text(
                        entry.timeLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppPalette.inkSoft,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (isPushing || isFailed) ...[
                        const SizedBox(height: 2),
                        Text(
                          isFailed ? 'failed' : 'pushing…',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isFailed ? AppPalette.accent : const Color(0xFFB45309),
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                        ),
                      ],
                      if (isAlreadyPushed || isQueueDuplicate || isDuplicate) ...[
                        const SizedBox(height: 2),
                        Text(
                          isAlreadyPushed
                              ? 'Duplicate: Already Pushed'
                              : isQueueDuplicate
                                  ? 'Duplicate: Already Exists In Queue'
                                  : 'Duplicate: Already Exists',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppPalette.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                        ),
                      ],
                      if (entry.editState != QueueEditState.none) ...[
                        const SizedBox(height: 2),
                        Text(
                          isUnderEdit ? 'under edit' : 'invoice edited',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isUnderEdit ? AppPalette.muted : AppPalette.pen,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // A "Garbage invoice" (failed scan) never became a voucher, so it
              // has no meaningful amount — omit the ₹0 that would otherwise show.
              if (entry.scanResult?['__garbage'] != true)
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
