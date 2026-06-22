import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';

class PushQueueService {
  PushQueueService({required this.onEntriesChanged});

  final void Function(List<QueueEntry> entries) onEntriesChanged;

  RealtimeChannel? _channel;
  List<QueueEntry> _entries = [];

  static bool isActiveStatus(String? status) =>
      status == 'pending' || status == 'push_now' || status == 'failed';

  Future<void> subscribe() async {
    await refresh();

    _channel = Supabase.instance.client
        .channel('push_queue_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            final row = payload.newRecord;
            if (!isActiveStatus(row['status'] as String?)) return;
            final entry = rowToEntry(row);
            _entries = [entry, ..._entries];
            onEntriesChanged(List.of(_entries));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            final deletedId = payload.oldRecord['id']?.toString();
            if (deletedId == null) return;
            _entries = _entries
                .where((e) => e.id != 'supabase_$deletedId')
                .toList();
            onEntriesChanged(List.of(_entries));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            final row = payload.newRecord;
            final newStatus = row['status'] as String?;
            final entryId = 'supabase_${row['id']}';
            // A row only leaves the live queue once it's actually pushed (it
            // moves to History). Every other status — pending/push_now/failed
            // AND any transient status the backend sets in between — keeps the
            // row visible, so a just-pushed voucher doesn't vanish and then
            // reappear on the next refresh.
            if (newStatus == 'pushed') {
              _entries = _entries.where((e) => e.id != entryId).toList();
            } else {
              var updated = rowToEntry(row);
              final exists = _entries.any((e) => e.id == entryId);
              // Supabase Realtime's column cache can lag a freshly-added column,
              // so an UPDATE echo may omit edit_state and rowToEntry would read
              // it as none — wiping the "under edit"/"invoice edited" tag. Keep
              // the editState we already have when the payload doesn't carry the
              // column; it's seeded authoritatively by refresh()/PostgREST and
              // the local edit flow, not by these echoes.
              if (exists && !row.containsKey('edit_state')) {
                final prior = _entries.firstWhere((e) => e.id == entryId);
                updated = updated.copyWith(editState: prior.editState);
              }
              _entries = exists
                  ? _entries.map((e) => e.id == entryId ? updated : e).toList()
                  : [updated, ..._entries];
            }
            onEntriesChanged(List.of(_entries));
          },
        )
        .subscribe();
  }

  // Re-fetches the active queue rows from Supabase. Used for the initial load
  // and for pull-to-refresh on the queue screen.
  Future<void> refresh() async {
    try {
      final response = await Supabase.instance.client
          .from('push_queue')
          .select('id, status, created_at, voucher_payload, source_payload, edit_state, pushed_at, error_message')
          .inFilter('status', ['pending', 'push_now', 'failed'])
          .order('created_at', ascending: false);

      _entries = (response as List)
          .cast<Map<String, dynamic>>()
          .map(rowToEntry)
          .toList();
      onEntriesChanged(List.of(_entries));
    } catch (_) {}
  }

  void unsubscribe() => _channel?.unsubscribe();

  static Map<String, dynamic> parsePayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  static QueueEntry rowToEntry(Map<String, dynamic> row) {
    final payload = parsePayload(row['voucher_payload']);
    final partyName = payload['party_name'] as String? ?? 'Unknown';
    // Classify by voucher_type: "GST SALE" → sale, "Purchase" → purchase.
    final voucherType = (payload['voucher_type'] as String? ?? '').toUpperCase();
    final type = voucherType.contains('SALE')
        ? TransactionType.sale
        : TransactionType.purchase;
    final ledgers =
        (payload['ledger_entries'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    final amount = ledgers.isNotEmpty
        ? ((ledgers.first['amount'] as num?)?.toDouble() ?? 0.0).abs()
        : 0.0;
    final createdAt =
        (DateTime.tryParse(row['created_at'] as String? ?? ''))?.toLocal() ??
            DateTime.now();

    return QueueEntry(
      id: 'supabase_${row['id']}',
      type: type,
      party: partyName,
      amount: amount,
      dayLabel: toDateLabel(createdAt),
      timeLabel: toTimeLabel(createdAt),
      sortKey: createdAt.millisecondsSinceEpoch,
      editState: QueueEditState.fromDb(row['edit_state'] as String?),
      scanResult: {
        ...payload,
        '__row_id': row['id']?.toString() ?? '',
        '__status': row['status'] as String? ?? 'pending',
        '__pushed_at': row['pushed_at'] as String?,
        '__error_message': row['error_message'] as String?,
        '__source_payload': parsePayload(row['source_payload']),
      },
    );
  }

  static String toDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month]}';
  }

  static String toTimeLabel(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
