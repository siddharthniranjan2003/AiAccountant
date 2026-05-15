import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/voucher_detail_sheet.dart';
import '../core/models.dart';
import '../core/constants.dart';
import '../core/palette.dart';
import '../core/seed_data.dart';
import '../core/utils.dart';
import '../widgets/screen_frame.dart';
import '../widgets/app_top_tabs.dart';
import '../widgets/queue_table_header.dart';
import '../widgets/queue_row_tile.dart';
import '../widgets/toast_stack.dart';
import '../widgets/spreadsheet_sheet.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
    required this.rows,
    required this.onRowsChanged,
    required this.tabIndex,
    required this.onTabChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;
  final List<QueueEntry> rows;
  final ValueChanged<List<QueueEntry>> onRowsChanged;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final List<ToastEntry> _toasts = <ToastEntry>[];

  TransactionType get _activeType =>
      widget.tabIndex == 0 ? TransactionType.sale : TransactionType.purchase;

  List<QueueEntry> get _visibleRows =>
      widget.rows.where((entry) => entry.type == _activeType).toList();

  String _showToast(
    String message, {
    required ToastKind kind,
    Duration? autoDismiss,
  }) {
    final toast = ToastEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      message: message,
      kind: kind,
    );

    setState(() {
      _toasts.add(toast);
    });

    if (autoDismiss != null) {
      Future<void>.delayed(autoDismiss, () {
        if (!mounted) return;
        _dismissToast(toast.id);
      });
    }

    return toast.id;
  }

  void _dismissToast(String id) {
    setState(() {
      _toasts.removeWhere((toast) => toast.id == id);
    });
  }

  void _updateEntry(
    String id,
    QueueEntry Function(QueueEntry current) transform,
  ) {
    widget.onRowsChanged(
      widget.rows
          .map((entry) => entry.id == id ? transform(entry) : entry)
          .toList(),
    );
  }

  void _openScanResultSheet(Map<String, dynamic> data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScanResultSheet(data: data),
    );
  }

  void _openVoucherDetailSheet(Map<String, dynamic> payload) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoucherDetailSheet(payload: payload),
    );
  }

  Future<void> _openChallanSheet(QueueEntry entry) async {
    if (entry.status == QueueStatus.processing) return;

    if (entry.scanResult != null) {
      // OCR scan result has 'ocr' key; voucher payload has 'voucher_type'
      if (entry.scanResult!.containsKey('voucher_type')) {
        _openVoucherDetailSheet(entry.scanResult!);
      } else {
        _openScanResultSheet(entry.scanResult!);
      }
      return;
    }

    final didConfirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppSpreadsheetSheet(
          fileName: 'challan_${sheetSlug(entry.party)}.xlsx',
          toolbarItems: const ['File', 'Edit', 'View', 'Σ', '%'],
          columnLabels: const [
            'Item',
            'HSN',
            'Qty',
            'Rate',
            'GST%',
            'Amount'
          ],
          columnWidths: const [42, 220, 88, 70, 84, 78, 108],
          rows: buildChallanRows(entry.party),
          footerLeading: 'Sheet1 · 5 line items',
          footerTrailing: 'Σ ₹2,604.26',
          trailingAction: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side:
                    const BorderSide(color: AppPalette.ink, width: 1.3),
              ),
            ),
            child: const Text('Done'),
          ),
        );
      },
    );

    if (didConfirm == true) {
      await _processSingleEntry(entry);
    }
  }

  Future<void> _processSingleEntry(QueueEntry entry) async {
    _updateEntry(
      entry.id,
      (current) =>
          current.copyWith(checked: true, status: QueueStatus.processing),
    );

    final processingToast = _showToast(
      'Your ${entry.type.label.toLowerCase()} challan for ${entry.party} is being processed…',
      kind: ToastKind.processing,
    );

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    _dismissToast(processingToast);
    _updateEntry(
      entry.id,
      (current) =>
          current.copyWith(checked: true, status: QueueStatus.done),
    );
    _showToast(
      '${entry.party} · ${entry.type.label.toLowerCase()} challan is done',
      kind: ToastKind.success,
      autoDismiss: const Duration(milliseconds: 2600),
    );
  }

  Map<String, List<QueueEntry>> _groupRows(List<QueueEntry> rows) {
    final groups = <String, List<QueueEntry>>{};
    for (final row in rows) {
      groups.putIfAbsent(row.dayLabel, () => <QueueEntry>[]).add(row);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groupedRows = _groupRows(_visibleRows);
    final serialLookup = <String, int>{
      for (int index = 0; index < _visibleRows.length; index++)
        _visibleRows[index].id: index + 1,
    };

    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      overlays: [
        if (_toasts.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: kBottomNavHeight + 12,
            child: ToastStack(toasts: _toasts),
          ),
      ],
      body: Column(
        children: [
          AppTopTabs(
            labels: const ['Sale', 'Purchase'],
            selectedIndex: widget.tabIndex,
            onSelected: widget.onTabChanged,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  const QueueTableHeader(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 18),
                      children: [
                        for (final group in groupedRows.entries) ...[
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(2, 4, 2, 6),
                            child: Text(
                              group.key,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppPalette.ink,
                                width: 1.4,
                              ),
                            ),
                            child: Column(
                              children: [
                                for (int index = 0;
                                    index < group.value.length;
                                    index++)
                                  QueueRowTile(
                                    entry: group.value[index],
                                    isFirst: index == 0,
                                    serialNumber: serialLookup[
                                        group.value[index].id]!,
                                    onPartyTap: group.value[index]
                                                .status ==
                                            QueueStatus.processing
                                        ? null
                                        : () => _openChallanSheet(
                                              group.value[index],
                                            ),
                                    onCheckboxTap:
                                        group.value[index].status ==
                                                QueueStatus.done
                                            ? null
                                            : () => _updateEntry(
                                                  group.value[index].id,
                                                  (current) =>
                                                      current.copyWith(
                                                    checked:
                                                        !current.checked,
                                                  ),
                                                ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanResultSheet extends StatefulWidget {
  const _ScanResultSheet({required this.data});

  final Map<String, dynamic> data;

  @override
  State<_ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends State<_ScanResultSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(
      () => setState(() => _query = _searchController.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header =
        ((widget.data['ocr'] as Map?) ?? {})['header'] as Map<String, dynamic>? ?? {};
    final vendorName = header['vendor_name'] as String? ?? '—';
    final invoiceNumber = header['invoice_number'] as String? ?? '—';
    final invoiceDate = header['invoice_date'] as String? ?? '—';
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
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
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendorName,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '$invoiceNumber · $invoiceDate',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppPalette.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 13),
            labelColor: AppPalette.ink,
            unselectedLabelColor: AppPalette.muted,
            indicatorColor: AppPalette.accent,
            indicatorWeight: 2.5,
            tabs: const [
              Tab(text: 'Invoice'),
              Tab(text: 'JSON'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _InvoiceTab(data: widget.data),
                _JsonTab(
                  data: widget.data,
                  searchController: _searchController,
                  query: _query,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Invoice table ─────────────────────────────────────────────────────

class _InvoiceTab extends StatelessWidget {
  const _InvoiceTab({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final header =
        ((data['ocr'] as Map?) ?? {})['header'] as Map<String, dynamic>? ?? {};
    final items =
        (data['matched_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final vendorName = header['vendor_name'] as String? ?? '—';
    final invoiceNumber = header['invoice_number'] as String? ?? '—';
    final invoiceDate = header['invoice_date'] as String? ?? '—';
    final invoiceTotal = (header['invoice_total'] as num?)?.toDouble() ?? 0.0;
    final discountPct = (header['discount_percent'] as num?)?.toDouble();
    final discountAmt = (header['discount_amount'] as num?)?.toDouble();
    final taxEntries =
        (header['tax_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppPalette.gridHeader,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.line, width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              _HeaderRow('Vendor', vendorName),
              _HeaderRow('Invoice #', invoiceNumber),
              _HeaderRow('Date', invoiceDate),
              if (discountPct != null && discountAmt != null)
                _HeaderRow(
                  'Discount',
                  '${discountPct.toStringAsFixed(0)}% · ${formatCurrency(discountAmt)}',
                ),
              for (final tax in taxEntries)
                _HeaderRow(
                  tax['ledger_name'] as String? ?? 'Tax',
                  formatCurrency((tax['amount'] as num?)?.toDouble() ?? 0),
                ),
              _HeaderRow('Total', formatCurrency(invoiceTotal), bold: true),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Line Items',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.gridHeader,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: AppPalette.line, width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Expanded(
                flex: 5,
                child: Text('Item',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              _ColHeader('Qty', flex: 2),
              _ColHeader('Rate', flex: 3),
              _ColHeader('Amount', flex: 3),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: AppPalette.line, width: 1.2),
              right: BorderSide(color: AppPalette.line, width: 1.2),
              bottom: BorderSide(color: AppPalette.line, width: 1.2),
            ),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++)
                _ItemRow(item: items[i]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Total  ${formatCurrency(invoiceTotal)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppPalette.inkSoft,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Tab 2: Searchable JSON ───────────────────────────────────────────────────

class _JsonTab extends StatelessWidget {
  const _JsonTab({
    required this.data,
    required this.searchController,
    required this.query,
  });

  final Map<String, dynamic> data;
  final TextEditingController searchController;
  final String query;

  @override
  Widget build(BuildContext context) {
    final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
    final allLines = prettyJson.split('\n');

    final lines = query.isEmpty
        ? List.generate(allLines.length, (i) => (i + 1, allLines[i]))
        : allLines
            .asMap()
            .entries
            .where((e) => e.value.toLowerCase().contains(query))
            .map((e) => (e.key + 1, e.value))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search JSON…',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: searchController.clear,
                    )
                  : null,
              filled: true,
              fillColor: AppPalette.gridHeader,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
        ),
        if (query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${lines.length} match${lines.length == 1 ? '' : 'es'}',
                style: const TextStyle(
                    fontSize: 11, color: AppPalette.muted),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final (lineNum, lineText) = lines[index];
              return _JsonLine(
                lineNumber: lineNum,
                text: lineText,
                query: query,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _JsonLine extends StatelessWidget {
  const _JsonLine({
    required this.lineNumber,
    required this.text,
    required this.query,
  });

  final int lineNumber;
  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.65,
      color: AppPalette.inkSoft,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 38,
          child: Text(
            '$lineNumber',
            textAlign: TextAlign.right,
            style: mono.copyWith(color: AppPalette.muted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: query.isEmpty
              ? Text(text, style: mono)
              : _highlighted(text, query, mono),
        ),
      ],
    );
  }

  Widget _highlighted(String text, String query, TextStyle base) {
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;

    while ((idx = lower.indexOf(query, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFD54F),
          color: AppPalette.ink,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + query.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(style: base, children: spans),
    );
  }
}

// ── Shared sub-widgets ───────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  const _HeaderRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppPalette.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? AppPalette.ink : AppPalette.inkSoft,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label, {required this.flex});

  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['stock_item_name'] as String? ?? '—';
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
    final rate = (item['rate'] as num?)?.toDouble() ?? 0;
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final unit = item['unit'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppPalette.line.withValues(alpha: 0.6)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.pen,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${qty % 1 == 0 ? qty.toInt() : qty} $unit'.trim(),
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppPalette.inkSoft),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              formatCurrency(rate),
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppPalette.inkSoft),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              formatCurrency(amount),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkSoft,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
