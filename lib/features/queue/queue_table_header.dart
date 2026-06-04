import 'package:flutter/material.dart';
import '../../core/palette.dart';

class QueueTableHeader extends StatelessWidget {
  const QueueTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.gridHeader.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.ink, width: 1.3),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, child: _TextCell(text: '#', align: TextAlign.left, isHeader: true)),
          const SizedBox(width: 8),
          const Expanded(child: _TextCell(text: 'Party', align: TextAlign.left, isHeader: true)),
          const _TextCell(text: 'Amount', align: TextAlign.right, isHeader: true),
        ],
      ),
    );
  }
}

class _TextCell extends StatelessWidget {
  const _TextCell({required this.text, this.align = TextAlign.left, this.isHeader = false});

  final String text;
  final TextAlign align;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.ink,
            fontWeight: isHeader ? FontWeight.w800 : FontWeight.w700,
          ),
    );
  }
}
