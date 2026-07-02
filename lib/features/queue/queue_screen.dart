import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models.dart';
import '../../core/palette.dart';
import '../../shared/screen_frame.dart';
import '../../shared/app_top_tabs.dart';
import 'queue_table_header.dart';
import 'queue_row_tile.dart';
import 'queue_loading_tile.dart';
import 'scan_result_sheet.dart';
import 'voucher_detail_sheet.dart';
import 'garbage_invoice_sheet.dart';

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
    this.garbageRows = const [],
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
  // Scans that failed to parse into a voucher, as "Garbage invoice" rows. Filtered
  // to the active tab and pinned above the day groups; tapping one opens an
  // image-only sheet with a delete action.
  final List<QueueEntry> garbageRows;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final Map<String, List<Map<String, dynamic>>> _savedEdits = {};
  // Local "under edit"/"invoice edited" tags, keyed by row id. Kept as a
  // render-time overlay (never written back through onRowsChanged) so the
  // realtime stream stays the sole writer of the row list — otherwise the
  // created_at bump's realtime event and a local row rewrite race and can drop
  // the just-edited row.
  final Map<String, QueueEditState> _editMarkers = {};

  TransactionType get _activeType =>
      widget.tabIndex == 0 ? TransactionType.sale : TransactionType.purchase;

  // Filtered to the active tab, tagged with any local edit marker, and sorted
  // newest-first by created_at. Sorting the flat list before grouping/serials
  // makes day headers, within-day order, and serial numbers all consistent.
  List<QueueEntry> get _visibleRows =>
      widget.rows.where((entry) => entry.type == _activeType).map((entry) {
        final marker = _editMarkers[entry.id];
        return marker == null ? entry : entry.copyWith(editState: marker);
      }).toList()
        ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

  void _openScanResultSheet(Map<String, dynamic> data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScanResultSheet(data: data),
    );
  }

  void _openVoucherDetailSheet(QueueEntry entry) {
    // entry.editState already reflects the persisted tag (and any optimistic
    // overlay applied in _visibleRows), so seed the session trackers from it —
    // simply viewing and closing a tagged row then leaves it untouched.
    final marker = entry.editState;
    final wasAlreadyEditing = marker == QueueEditState.underEdit;
    // Seed the session trackers from the row's current marker so that simply
    // viewing (and closing without touching) a tagged row leaves it untouched.
    bool wasEditing = wasAlreadyEditing;
    bool everSaved = marker == QueueEditState.edited;
    bool touched = false;
    List<Map<String, dynamic>> latestItems =
        wasAlreadyEditing ? (_savedEdits[entry.id] ?? <Map<String, dynamic>>[]) : [];
    final screenWidth = MediaQuery.of(context).size.width;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Lift Material's default modal width cap so the sheet can use ~90% of a
      // wide (web/desktop) screen for the side-by-side image+summary layout.
      // 900 matches kDesktopBreakpoint (context.isWideScreen) so the 90% width
      // and the two-pane layout switch on together.
      constraints: BoxConstraints(
        maxWidth: screenWidth >= 900 ? screenWidth * 0.9 : double.infinity,
      ),
      builder: (ctx) => VoucherDetailSheet(
        payload: entry.scanResult!,
        imageBytes: entry.imageBytes,
        initialIsEditing: wasAlreadyEditing,
        initialEditableItems: wasAlreadyEditing ? _savedEdits[entry.id] : null,
        onEditStateChanged: (isEditing, items, saved) {
          touched = true;
          wasEditing = isEditing;
          everSaved = saved;
          latestItems = items;
        },
        onDiscard: () => _discardEntry(entry),
        // After a push, re-fetch from Supabase so the row reflects its new
        // push_now status (instead of vanishing until a manual reload).
        onPushed: widget.onRefresh,
      ),
    ).then((_) async {
      if (!mounted) return;
      // Nothing happened this session — keep the row (and any prior tag) as is.
      if (!touched) return;
      var changed = false;
      if (wasEditing) {
        // Case 1 — closed mid-edit. Stash the in-progress items, tag the row
        // "under edit" and float it to the top (bump created_at).
        _savedEdits[entry.id] = latestItems;
        setState(() => _editMarkers[entry.id] = QueueEditState.underEdit);
        await _persistEditState(entry, QueueEditState.underEdit, bump: true);
        changed = true;
      } else if (everSaved) {
        // Case 2 — edits were saved. Tag "invoice edited" and float to the top.
        _savedEdits.remove(entry.id);
        setState(() => _editMarkers[entry.id] = QueueEditState.edited);
        await _persistEditState(entry, QueueEditState.edited, bump: true);
        changed = true;
      } else {
        // Edited then reverted back to the original — clear any tag. Only writes
        // to the server when the row was actually tagged when opened, so a plain
        // view → edit → revert on an untagged row doesn't fire a spurious update.
        _savedEdits.remove(entry.id);
        setState(() => _editMarkers.remove(entry.id));
        if (marker != QueueEditState.none) {
          await _persistEditState(entry, QueueEditState.none, bump: false);
          changed = true;
        }
      }
      // Reconcile the row from the server. PostgREST reliably returns edit_state
      // (unlike a realtime echo, whose column cache can lag the ALTER), so the
      // tag lands durably in the queue list instead of living only in the local
      // overlay — which is what made it flash and then vanish on a rebuild.
      if (changed && mounted) await widget.onRefresh();
    });
  }

  // Persists the row's edit tag to the push_queue.edit_state column so it
  // survives a cold start and shows on every client (restored by rowToEntry).
  // For the under-edit / edited cases it also bumps created_at to now, so the
  // newest-first sort floats the just-edited voucher to the top. Both ride a
  // single targeted update — the realtime UPDATE it triggers is the sole writer
  // of the row list, and the local marker overlay in _visibleRows re-applies the
  // tag on top of the rebuilt row.
  Future<void> _persistEditState(
    QueueEntry entry,
    QueueEditState state, {
    required bool bump,
  }) async {
    final rowId = entry.scanResult?['__row_id'] as String?;
    if (rowId == null || rowId.isEmpty) return;
    final update = <String, dynamic>{'edit_state': state.dbValue};
    if (bump) {
      update['created_at'] = DateTime.now().toUtc().toIso8601String();
    }
    try {
      await Supabase.instance.client
          .from('push_queue')
          .update(update)
          .eq('id', rowId);
    } catch (_) {}
  }

  // Drops the row from the in-memory list only — no Supabase write. A pull-to-
  // refresh (or the next realtime event) re-fetches it from the server.
  void _discardEntry(QueueEntry entry) {
    widget.onRowsChanged(
      widget.rows.where((e) => e.id != entry.id).toList(),
    );
    _savedEdits.remove(entry.id);
    _editMarkers.remove(entry.id);
  }

  // Opens an image-only sheet for a failed scan ("Garbage invoice") with a delete
  // action. Keyed by the scan_jobs id carried on the marker scanResult.
  void _openGarbageSheet(QueueEntry entry) {
    final scanJobId = entry.scanResult?['__scan_job_id'] as String?;
    if (scanJobId == null || scanJobId.isEmpty) return;
    final pageCount = (entry.scanResult?['__page_count'] as num?)?.toInt() ?? 0;
    final screenWidth = MediaQuery.of(context).size.width;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: screenWidth >= 900 ? screenWidth * 0.9 : double.infinity,
      ),
      builder: (ctx) => GarbageInvoiceSheet(
        scanJobId: scanJobId,
        pageCount: pageCount,
      ),
    );
  }

  void _openChallanSheet(QueueEntry entry) {
    if (entry.scanResult?['__garbage'] == true) {
      _openGarbageSheet(entry);
      return;
    }
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

  // Ids of purchase rows whose invoice reference already appeared on an older
  // queue row — i.e. the same invoice uploaded again. The supplier invoice number
  // lives in voucher_payload.reference (voucher_number is unreliable/blank on live
  // data). Rows arrive sorted newest-first, so the oldest occurrence of each
  // reference is the original and every newer copy is tagged a duplicate. Blank
  // references never match. Sale rows are never flagged (dedupe is purchase-only).
  Set<String> _queueDuplicateIds(List<QueueEntry> rows) {
    if (_activeType != TransactionType.purchase) return const {};
    final duplicates = <String>{};
    final seenReferences = <String>{};
    for (final entry in rows.reversed) {
      final reference =
          (entry.scanResult?['reference'] as String?)?.trim() ?? '';
      if (reference.isEmpty) continue;
      if (!seenReferences.add(reference)) duplicates.add(entry.id);
    }
    return duplicates;
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleRows;
    final groupedRows = _groupRows(visibleRows);
    final queueDuplicateIds = _queueDuplicateIds(visibleRows);
    final serialLookup = <String, int>{
      for (int index = 0; index < visibleRows.length; index++)
        visibleRows[index].id: index + 1,
    };
    // Failed scans for this tab, newest-first — rendered as a pinned "Garbage
    // invoice" block above the day groups (kept out of the main serial numbering).
    final garbageRows = widget.garbageRows
        .where((entry) => entry.type == _activeType)
        .toList()
      ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

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
                        if (garbageRows.isNotEmpty) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppPalette.accent, width: 1.4),
                            ),
                            child: Column(
                              children: [
                                for (int index = 0; index < garbageRows.length; index++)
                                  QueueRowTile(
                                    entry: garbageRows[index],
                                    isFirst: index == 0,
                                    serialNumber: index + 1,
                                    onPartyTap: () => _openChallanSheet(garbageRows[index]),
                                  ),
                              ],
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
                                    isQueueDuplicate:
                                        queueDuplicateIds.contains(group.value[index].id),
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
