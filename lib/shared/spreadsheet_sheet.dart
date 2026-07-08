import 'package:flutter/material.dart';
import '../core/palette.dart';
import '../core/utils.dart';

class AppSpreadsheetSheet extends StatefulWidget {
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
    this.onShare,
    this.sumColumnIndex,
    this.footerLeadingLabel,
    this.countUnit = 'rows',
    this.cachedDate,
  });

  final String fileName;
  /// Optional "cached on" label shown to the right of [fileName] in the header.
  final String? cachedDate;
  final List<String> toolbarItems;
  final List<String> columnLabels;
  final List<double> columnWidths;
  final List<List<String>> rows;
  final String footerLeading;
  final String footerTrailing;
  final Widget trailingAction;
  final VoidCallback? onShare;

  /// When set, the footer leading shows "[footerLeadingLabel] - ₹[total]",
  /// where the total is the sum of this cell index across the visible rows
  /// (recomputed live as the search filter narrows the rows).
  final int? sumColumnIndex;
  final String? footerLeadingLabel;
  final String countUnit;

  @override
  State<AppSpreadsheetSheet> createState() => _AppSpreadsheetSheetState();
}

class _AppSpreadsheetSheetState extends State<AppSpreadsheetSheet> {
  bool _showSearch = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<List<String>> get _filteredRows {
    if (_query.isEmpty) return widget.rows;
    final q = _query.toLowerCase();
    return widget.rows
        .where((r) => r.isNotEmpty && r[0].toLowerCase().contains(q))
        .toList();
  }

  String get _footerLeading {
    if (widget.sumColumnIndex == null) return widget.footerLeading;
    final idx = widget.sumColumnIndex!;
    num total = 0;
    for (final row in _filteredRows) {
      if (idx < row.length) total += _cellToNum(row[idx]);
    }
    return '${widget.footerLeadingLabel} - ${formatCurrency(total)}';
  }

  String get _footerTrailing {
    if (widget.sumColumnIndex != null) {
      return '${_filteredRows.length} ${widget.countUnit}';
    }
    if (_query.isEmpty) return widget.footerTrailing;
    final count = _filteredRows.length;
    final total = widget.rows.length;
    return '$count of $total rows';
  }

  /// Parses a grouped cell value (e.g. "1,36,433") into a number, ignoring
  /// thousands separators and any non-numeric decoration.
  num _cellToNum(String cell) {
    final cleaned = cell.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return num.tryParse(cleaned) ?? 0;
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    child: _showSearch
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: InputDecoration(
                              hintText: 'Search item name…',
                              hintStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppPalette.muted),
                              isDense: true,
                              border: InputBorder.none,
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          )
                        : Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (widget.cachedDate != null) ...[
                                const SizedBox(width: 10),
                                Text(
                                  widget.cachedDate!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppPalette.muted),
                                ),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _toggleSearch,
                    icon: Icon(
                      _showSearch
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      size: 20,
                      color: _showSearch
                          ? AppPalette.accent
                          : AppPalette.inkSoft,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  if (widget.onShare != null)
                    IconButton(
                      onPressed: widget.onShare,
                      icon: const Icon(
                        Icons.ios_share_rounded,
                        size: 20,
                        color: AppPalette.inkSoft,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  const SizedBox(width: 10),
                  widget.trailingAction,
                ],
              ),
            ),
            Expanded(
              child: _LazySpreadsheet(
                columnLabels: widget.columnLabels,
                columnWidths: widget.columnWidths,
                rows: _filteredRows,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppPalette.ink, width: 1.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _footerLeading,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    _footerTrailing,
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

class _LazySpreadsheet extends StatefulWidget {
  const _LazySpreadsheet({
    required this.columnLabels,
    required this.columnWidths,
    required this.rows,
  });

  final List<String> columnLabels;
  final List<double> columnWidths;
  final List<List<String>> rows;

  @override
  State<_LazySpreadsheet> createState() => _LazySpreadsheetState();
}

class _LazySpreadsheetState extends State<_LazySpreadsheet> {
  final _hScroll = ScrollController();
  static const double _borderWidth = 1.3;

  double get _totalWidth =>
      widget.columnWidths.fold(0.0, (sum, w) => sum + w) + _borderWidth * 2;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = List<String>.generate(
      widget.columnLabels.length,
      (i) => String.fromCharCode(65 + i),
    );

    return Scrollbar(
      controller: _hScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Container(
          width: _totalWidth,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppPalette.ink, width: _borderWidth),
          ),
          child: Column(
            children: [
              SpreadsheetGridRow(
                cells: ['', ...letters],
                widths: widget.columnWidths,
                isHeader: true,
                backgroundColor: AppPalette.gridHeader,
              ),
              SpreadsheetGridRow(
                cells: ['', ...widget.columnLabels],
                widths: widget.columnWidths,
                isHeader: true,
                backgroundColor: AppPalette.gridHeader.withValues(alpha: 0.58),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: widget.rows.length,
                  itemBuilder: (context, i) {
                    return SpreadsheetGridRow(
                      cells: ['${i + 1}', ...widget.rows[i]],
                      widths: widget.columnWidths,
                      isHeader: false,
                      backgroundColor: i.isEven
                          ? Colors.white
                          : AppPalette.paper.withValues(alpha: 0.5),
                    );
                  },
                ),
              ),
            ],
          ),
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
        color: Colors.white.withValues(alpha: 0.74),
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
            backgroundColor: AppPalette.gridHeader.withValues(alpha: 0.58),
          ),
          for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
            SpreadsheetGridRow(
              cells: ['${rowIndex + 1}', ...rows[rowIndex]],
              widths: columnWidths,
              isHeader: false,
              backgroundColor: rowIndex.isEven
                  ? Colors.white
                  : AppPalette.paper.withValues(alpha: 0.5),
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
            color: AppPalette.ink.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
      ),
      // IntrinsicHeight gives the Row a concrete height (the tallest cell) so
      // CrossAxisAlignment.stretch can make every cell — and its divider —
      // full-height once cells wrap to multiple lines.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          for (int index = 0; index < cells.length; index++)
            Container(
              width: widths[index],
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  right: index == cells.length - 1
                      ? BorderSide.none
                      : BorderSide(
                          color: AppPalette.ink.withValues(alpha: 0.14),
                        ),
                ),
              ),
              // Wrap the full text onto extra lines instead of truncating with
              // an ellipsis when the column width can't fit it on one line.
              child: Align(
                alignment:
                    index == 0 ? Alignment.center : Alignment.centerLeft,
                child: Text(
                  cells[index],
                  softWrap: true,
                  textAlign: index == 0 ? TextAlign.center : TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cells[index].isEmpty
                            ? AppPalette.muted
                            : AppPalette.ink,
                        fontWeight:
                            isHeader ? FontWeight.w800 : FontWeight.w600,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
