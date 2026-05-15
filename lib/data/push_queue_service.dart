import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';

class PushQueueService {
  PushQueueService({required this.onEntriesChanged});

  final void Function(List<QueueEntry> entries) onEntriesChanged;

  RealtimeChannel? _channel;
  List<QueueEntry> _entries = [];

  static bool isActiveStatus(String? status) =>
      status == 'pending' || status == 'push_now';

  Future<void> subscribe() async {
    try {
      final response = await Supabase.instance.client
          .from('push_queue')
          .select('id, status, created_at, voucher_payload')
          .inFilter('status', ['pending', 'push_now'])
          .order('created_at', ascending: false);

      _entries = (response as List)
          .cast<Map<String, dynamic>>()
          .map(rowToEntry)
          .toList();
      onEntriesChanged(List.of(_entries));
    } catch (_) {}

    _channel = Supabase.instance.client
        .channel('push_queue_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            final row = payload.newRecord;
            if (!isActiveStatus(row['status'] as String?)) return;
            _entries = [rowToEntry(row), ..._entries];
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
            if (isActiveStatus(newStatus)) {
              final updated = rowToEntry(row);
              final exists = _entries.any((e) => e.id == entryId);
              _entries = exists
                  ? _entries.map((e) => e.id == entryId ? updated : e).toList()
                  : [updated, ..._entries];
            } else {
              _entries = _entries.where((e) => e.id != entryId).toList();
            }
            onEntriesChanged(List.of(_entries));
          },
        )
        .subscribe();
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
      type: TransactionType.purchase,
      party: partyName,
      amount: amount,
      dayLabel: toDateLabel(createdAt),
      timeLabel: toTimeLabel(createdAt),
      scanResult: {
        ...payload,
        '__row_id': row['id']?.toString() ?? '',
        '__status': row['status'] as String? ?? 'pending',
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
