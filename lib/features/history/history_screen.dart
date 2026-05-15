import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models.dart';
import '../../data/seed_data.dart';
import '../../shared/screen_frame.dart';
import '../../shared/app_top_tabs.dart';
import '../queue/voucher_detail_sheet.dart';
import 'history_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _filterIndex = 0;

  final Map<String, Map<String, dynamic>> _pushedRowsById = {};
  RealtimeChannel? _channel;

  List<HistoryEntry> get _purchaseHistory {
    final entries = _pushedRowsById.values.map(_rowToHistoryEntry).toList();
    entries.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return entries;
  }

  List<HistoryEntry> get _saleHistory =>
      seedHistoryEntries.where((e) => e.type == TransactionType.sale).toList();

  @override
  void initState() {
    super.initState();
    _fetchAndSubscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchAndSubscribe() async {
    try {
      final response = await Supabase.instance.client
          .from('push_queue')
          .select('id, status, pushed_at, created_at, voucher_payload')
          .eq('status', 'pushed')
          .order('pushed_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _pushedRowsById.clear();
        for (final row in (response as List).cast<Map<String, dynamic>>()) {
          final id = row['id']?.toString() ?? '';
          if (id.isNotEmpty) _pushedRowsById[id] = row;
        }
      });
    } catch (_) {}

    _channel = Supabase.instance.client
        .channel('history_push_queue')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            if (!mounted) return;
            final row = payload.newRecord;
            if (row['status'] != 'pushed') return;
            final id = row['id']?.toString() ?? '';
            if (id.isEmpty) return;
            setState(() => _pushedRowsById[id] = row);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            if (!mounted) return;
            final row = payload.newRecord;
            final id = row['id']?.toString() ?? '';
            if (id.isEmpty) return;
            setState(() {
              if (row['status'] == 'pushed') {
                _pushedRowsById[id] = row;
              } else {
                _pushedRowsById.remove(id);
              }
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            if (!mounted) return;
            final id = payload.oldRecord['id']?.toString() ?? '';
            if (id.isEmpty) return;
            setState(() => _pushedRowsById.remove(id));
          },
        )
        .subscribe();
  }

  static Map<String, dynamic> _parsePayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  static HistoryEntry _rowToHistoryEntry(Map<String, dynamic> row) {
    final payload = _parsePayload(row['voucher_payload']);
    final partyName = payload['party_name'] as String? ?? 'Unknown';
    final ledgers =
        (payload['ledger_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final amount = ledgers.isNotEmpty
        ? ((ledgers.first['amount'] as num?)?.toDouble() ?? 0.0).abs()
        : 0.0;

    final dt =
        (DateTime.tryParse(row['pushed_at'] as String? ?? '') ??
                DateTime.tryParse(row['created_at'] as String? ?? ''))
            ?.toLocal() ??
        DateTime.now();

    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const fullMonths = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    return HistoryEntry(
      party: partyName,
      type: TransactionType.purchase,
      amount: amount,
      dateLabel: '${dt.day} ${months[dt.month]}',
      monthLabel: '${fullMonths[dt.month]} ${dt.year}',
      sortKey: dt.millisecondsSinceEpoch,
      rowId: row['id']?.toString() ?? '',
    );
  }

  void _openSheet(HistoryEntry entry) {
    if (entry.rowId.isEmpty) return;
    final row = _pushedRowsById[entry.rowId];
    if (row == null) return;
    final payload = _parsePayload(row['voucher_payload']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoucherDetailSheet(payload: {
        ...payload,
        '__row_id': entry.rowId,
        '__status': row['status'] as String? ?? 'pushed',
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = switch (_filterIndex) {
      0 => [..._saleHistory, ..._purchaseHistory],
      1 => _saleHistory,
      _ => _purchaseHistory,
    };

    final grouped = <String, List<HistoryEntry>>{};
    for (final entry in visibleItems) {
      grouped.putIfAbsent(entry.monthLabel, () => []).add(entry);
    }

    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      body: Column(
        children: [
          AppTopTabs(
            labels: const ['All', 'Sale', 'Purchase'],
            selectedIndex: _filterIndex,
            onSelected: (index) => setState(() => _filterIndex = index),
          ),
          Expanded(
            child: visibleItems.isEmpty
                ? const Center(
                    child: Text('No records', style: TextStyle(color: Color(0xFF8A8576))),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    children: [
                      for (final group in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                          child: Text(
                            group.key,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        for (final entry in group.value) ...[
                          HistoryCard(
                            entry: entry,
                            onTap: entry.rowId.isNotEmpty ? () => _openSheet(entry) : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
