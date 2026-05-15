import 'package:flutter/material.dart';
import '../../core/palette.dart';
import '../../core/constants.dart';

class QueueBulkBar extends StatelessWidget {
  const QueueBulkBar({
    super.key,
    required this.selectedCount,
    required this.onConfirm,
  });

  final int selectedCount;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kBulkBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF0D3),
        border: Border(top: BorderSide(color: AppPalette.ink, width: 1.2)),
      ),
      child: Row(
        children: [
          Text(
            '$selectedCount selected',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppPalette.line,
              disabledForegroundColor: AppPalette.inkSoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppPalette.ink, width: 1.3),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
