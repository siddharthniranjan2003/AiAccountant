import 'package:flutter/material.dart';
import '../../core/palette.dart';
import '../../core/models.dart';

class CaptureTypeDialog extends StatelessWidget {
  const CaptureTypeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: AppPalette.sheet,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppPalette.ink, width: 1.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'What is this?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: CaptureTypeOption(
                    label: 'Sale',
                    onTap: () => Navigator.of(context).pop(TransactionType.sale),
                  ),
                ),
                // Purchase capture temporarily hidden. This dialog is currently
                // unreachable anyway — app_shell defaults straight to Sale — so
                // restoring Purchase means uncommenting there too.
                // const SizedBox(width: 14),
                // Expanded(
                //   child: CaptureTypeOption(
                //     label: 'Purchase',
                //     onTap: () => Navigator.of(context).pop(TransactionType.purchase),
                //   ),
                // ),
              ],
            ),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft),
                children: const [
                  TextSpan(text: 'Then ', style: TextStyle(color: AppPalette.accent, fontWeight: FontWeight.w800)),
                  TextSpan(text: 'camera opens, already tagged'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CaptureTypeOption extends StatelessWidget {
  const CaptureTypeOption({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 122,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppPalette.ink, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppPalette.accent2.withValues(alpha: 0.35),
                border: Border.all(color: AppPalette.ink, width: 1.2),
              ),
              child: const Icon(Icons.inventory_2_rounded, color: AppPalette.accent, size: 18),
            ),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
