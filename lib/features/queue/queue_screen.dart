import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/palette.dart';
import '../../shared/screen_frame.dart';
import '../../shared/app_top_tabs.dart';
import 'queue_table_header.dart';
import 'queue_row_tile.dart';
import 'queue_loading_tile.dart';
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
    this.loadingCount = 0,
    this.oldestLoadingStart,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;
  final List<QueueEntry> rows;
  final ValueChanged<List<QueueEntry>> onRowsChanged;
  final Future<void> Function() onRefresh;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  // Number of in-flight parse requests for the active tab, and the start time of
  // the oldest one. Rendered as a single "Processing…" row with a count badge
  // and a timer ring at the top of the list.
  final int loadingCount;
  final DateTime? oldestLoadingStart;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final Map<String, List<Map<String, dynamic>>> _savedEdits = {};

  TransactionType get _activeType =>
      widget.tabIndex == 0 ? TransactionType.sale : TransactionType.purchase;

  // Filtered to the active tab and sorted newest-first by created_at. Sorting
  // the flat list before grouping/serials makes day headers, within-day order,
  // and serial numbers all consistent.
  List<QueueEntry> get _visibleRows =>
      widget.rows.where((entry) => entry.type == _activeType).toList()
        ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

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

  void _openChallanSheet(QueueEntry entry) {
    if (entry.invoiceExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Invoice Is Already In TallyPrime'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    final r = entry.scanResult;
    if (r == null) return;
    if (r.containsKey('voucher_type') ||
        r.containsKey('voucher_payload') ||
        r.containsKey('sale_voucher_payload') ||
        r.containsKey('parsed') ||
        r.containsKey('ocr')) {
      _openVoucherDetailSheet(entry);
    } else {
      _openScanResultSheet(r);
    }
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
    final visibleRows = _visibleRows;
    final groupedRows = _groupRows(visibleRows);
    final serialLookup = <String, int>{
      for (int index = 0; index < visibleRows.length; index++)
        visibleRows[index].id: index + 1,
    };

    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
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
                        if (widget.loadingCount > 0 &&
                            widget.oldestLoadingStart != null) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppPalette.ink, width: 1.4),
                            ),
                            child: QueueLoadingTile(
                              count: widget.loadingCount,
                              oldestStart: widget.oldestLoadingStart!,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
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
                                    onPartyTap: () => _openChallanSheet(group.value[index]),
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
