import 'package:flutter/material.dart';
import '../core/palette.dart';

class AppSpreadsheetSheet extends StatelessWidget {
  const AppSpreadsheetSheet({
    super.key,
    required this.fileName,
    required this.toolbarItems,
    required this.columnLabels,
    required this.columnWidths,
    required this.rows,
    required this.footerLeading,
    required this.footerTrailing,
    required this.trailingAction,
  });

  final String fileName;
  final List<String> toolbarItems;
  final List<String> columnLabels;
  final List<double> columnWidths;
  final List<List<String>> rows;
  final String footerLeading;
  final String footerTrailing;
  final Widget trailingAction;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: const BoxDecoration(
          color: AppPalette.sheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 56,
              height: 4,
              decoration: BoxDecoration(
                color: AppPalette.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppPalette.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailingAction,
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.gridHeader.withOpacity(0.6),
                border: Border(
                  top: BorderSide(
                      color: AppPalette.ink.withOpacity(0.18)),
                  bottom: BorderSide(
                      color: AppPalette.ink.withOpacity(0.18)),
                ),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final item in toolbarItems)
                    Text(
                      item,
                      style:
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: AppPalette.inkSoft,
                              ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SpreadsheetGrid(
                    columnLabels: columnLabels,
                    columnWidths: columnWidths,
                    rows: rows,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppPalette.ink, width: 1.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      footerLeading,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    footerTrailing,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpreadsheetGrid extends StatelessWidget {
  const SpreadsheetGrid({
    super.key,
    required this.columnLabels,
    required this.columnWidths,
    required this.rows,
  });

  final List<String> columnLabels;
  final List<double> columnWidths;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final letters = List<String>.generate(
      columnLabels.length,
      (index) => String.fromCharCode(65 + index),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.ink, width: 1.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpreadsheetGridRow(
            cells: [''] + letters,
            widths: columnWidths,
            isHeader: true,
            backgroundColor: AppPalette.gridHeader,
          ),
          SpreadsheetGridRow(
            cells: [''] + columnLabels,
            widths: columnWidths,
            isHeader: true,
            backgroundColor: AppPalette.gridHeader.withOpacity(0.58),
          ),
          for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
            SpreadsheetGridRow(
              cells: ['${rowIndex + 1}', ...rows[rowIndex]],
              widths: columnWidths,
              isHeader: false,
              backgroundColor: rowIndex.isEven
                  ? Colors.white
                  : AppPalette.paper.withOpacity(0.5),
            ),
        ],
      ),
    );
  }
}

class SpreadsheetGridRow extends StatelessWidget {
  const SpreadsheetGridRow({
    super.key,
    required this.cells,
    required this.widths,
    required this.isHeader,
    required this.backgroundColor,
  });

  final List<String> cells;
  final List<double> widths;
  final bool isHeader;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: AppPalette.ink.withOpacity(0.18),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          for (int index = 0; index < cells.length; index++)
            Container(
              width: widths[index],
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  right: index == cells.length - 1
                      ? BorderSide.none
                      : BorderSide(
                          color: AppPalette.ink.withOpacity(0.14),
                        ),
                ),
              ),
              child: Text(
                cells[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign:
                    index == 0 ? TextAlign.center : TextAlign.left,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cells[index].isEmpty
                          ? AppPalette.muted
                          : AppPalette.ink,
                      fontWeight: isHeader
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
