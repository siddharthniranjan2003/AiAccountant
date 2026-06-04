import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../data/seed_data.dart';
import '../../core/utils.dart';
import '../../shared/screen_frame.dart';
import '../../shared/app_top_tabs.dart';
import '../../shared/toast_stack.dart';
import '../../shared/spreadsheet_sheet.dart';
import 'queue_table_header.dart';
import 'queue_row_tile.dart';
import 'scan_result_sheet.dart';
import 'voucher_detail_sheet.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
    required this.rows,
    required this.onRowsChanged,
    required this.onRefresh,
    required this.tabIndex,
    required this.onTabChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;
  final List<QueueEntry> rows;
  final ValueChanged<List<QueueEntry>> onRowsChanged;
  final Future<void> Function() onRefresh;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final List<ToastEntry> _toasts = <ToastEntry>[];
  final Map<String, List<Map<String, dynamic>>> _savedEdits = {};

  TransactionType get _activeType =>
      widget.tabIndex == 0 ? TransactionType.sale : TransactionType.purchase;

  List<QueueEntry> get _visibleRows =>
      widget.rows.where((entry) => entry.type == _activeType).toList();

  String _showToast(String message, {required ToastKind kind, Duration? autoDismiss}) {
    final toast = ToastEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      message: message,
      kind: kind,
    );
    setState(() => _toasts.add(toast));
    if (autoDismiss != null) {
      Future<void>.delayed(autoDismiss, () {
        if (!mounted) return;
        _dismissToast(toast.id);
      });
    }
    return toast.id;
  }

  void _dismissToast(String id) {
    setState(() => _toasts.removeWhere((toast) => toast.id == id));
  }

  void _updateEntry(String id, QueueEntry Function(QueueEntry current) transform) {
    widget.onRowsChanged(
      widget.rows.map((entry) => entry.id == id ? transform(entry) : entry).toList(),
    );
  }

  void _openScanResultSheet(Map<String, dynamic> data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScanResultSheet(data: data),
    );
  }

  void _openVoucherDetailSheet(QueueEntry entry) {
    final wasAlreadyEditing = entry.isBeingEdited;
    _updateEntry(entry.id, (e) => e.copyWith(isBeingEdited: false));
    bool wasEditing = false;
    List<Map<String, dynamic>> latestItems = [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoucherDetailSheet(
        payload: entry.scanResult!,
        imageBytes: entry.imageBytes,
        initialIsEditing: wasAlreadyEditing,
        initialEditableItems: wasAlreadyEditing ? _savedEdits[entry.id] : null,
        onEditStateChanged: (isEditing, items) {
          wasEditing = isEditing;
          latestItems = items;
        },
        onDiscard: () => _discardEntry(entry),
      ),
    ).then((_) {
      if (!mounted) return;
      if (wasEditing) {
        _savedEdits[entry.id] = latestItems;
        _updateEntry(entry.id, (e) => e.copyWith(isBeingEdited: true));
      } else {
        _savedEdits.remove(entry.id);
      }
    });
  }

  // Drops the row from the in-memory list only — no Supabase write. A pull-to-
  // refresh (or the next realtime event) re-fetches it from the server.
  void _discardEntry(QueueEntry entry) {
    widget.onRowsChanged(
      widget.rows.where((e) => e.id != entry.id).toList(),
    );
    _savedEdits.remove(entry.id);
  }

  Future<void> _openChallanSheet(QueueEntry entry) async {
    if (entry.status == QueueStatus.processing) return;

    if (entry.scanResult != null) {
      final r = entry.scanResult!;
      if (r.containsKey('voucher_type') ||
          r.containsKey('voucher_payload') ||
          r.containsKey('sale_voucher_payload') ||
          r.containsKey('parsed') ||
          r.containsKey('ocr')) {
        _openVoucherDetailSheet(entry);
      } else {
        _openScanResultSheet(r);
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
          columnLabels: const ['Item', 'HSN', 'Qty', 'Rate', 'GST%', 'Amount'],
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
                side: const BorderSide(color: AppPalette.ink, width: 1.3),
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
    _updateEntry(entry.id, (current) => current.copyWith(checked: true, status: QueueStatus.processing));

    final processingToast = _showToast(
      'Your ${entry.type.label.toLowerCase()} challan for ${entry.party} is being processed…',
      kind: ToastKind.processing,
    );

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    _dismissToast(processingToast);
    _updateEntry(entry.id, (current) => current.copyWith(checked: true, status: QueueStatus.done));
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
                    child: RefreshIndicator(
                      onRefresh: widget.onRefresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 18),
                        children: [
                        for (final group in groupedRows.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
                            child: Text(
                              group.key,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppPalette.ink, width: 1.4),
                            ),
                            child: Column(
                              children: [
                                for (int index = 0; index < group.value.length; index++)
                                  QueueRowTile(
                                    entry: group.value[index],
                                    isFirst: index == 0,
                                    serialNumber: serialLookup[group.value[index].id]!,
                                    onPartyTap: group.value[index].status == QueueStatus.processing
                                        ? null
                                        : () => _openChallanSheet(group.value[index]),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        ],
                      ),
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
