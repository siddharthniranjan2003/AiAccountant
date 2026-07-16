import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_reporter.dart';
import '../core/models.dart';

class PushQueueService {
  PushQueueService({required this.onEntriesChanged});

  final void Function(List<QueueEntry> entries) onEntriesChanged;

  RealtimeChannel? _channel;
  List<QueueEntry> _entries = [];

  // Trimmed, non-blank supplier invoice references of already-pushed PURCHASE
  // rows (i.e. vouchers that moved to History). The queue's duplicate check reads
  // this to flag a re-uploaded invoice whose original has already been pushed —
  // those rows are no longer in _entries, so this is the only way the queue can
  // see them. Purchase-only, mirroring the queue-side dedupe.
  final Set<String> _pushedPurchaseReferences = {};
  Set<String> get pushedPurchaseReferences => _pushedPurchaseReferences;

  // The purchase reference on a raw push_queue row, or '' when blank/absent or
  // the row is a sale. Classification matches rowToEntry (SALE vs purchase).
  static String _purchaseReferenceOf(Map<String, dynamic> row) {
    final payload = parsePayload(row['voucher_payload']);
    final voucherType = (payload['voucher_type'] as String? ?? '').toUpperCase();
    if (voucherType.contains('SALE')) return '';
    return (payload['reference'] as String?)?.trim() ?? '';
  }

  static bool isActiveStatus(String? status) =>
      status == 'pending' || status == 'push_now' || status == 'failed';

  // Stock-item create jobs (voucher_payload.kind == 'stock_item') ride the same
  // push_queue table but are not vouchers — they have no party/items/amount and
  // would misrender as queue cards. The create-item sheet tracks its own row via
  // a per-row realtime channel, so the queue (and History) skip them entirely.
  static bool isStockItemRow(Map<String, dynamic> row) =>
      parsePayload(row['voucher_payload'])['kind'] == 'stock_item';

  // Realtime UPDATE echoes are not always whole rows, so patch the gaps from the
  // copy we already hold before anything reads the row.
  //
  // Postgres omits unchanged TOASTed values from the WAL, and TOAST kicks in once
  // a tuple tops ~2KB — which about a third of live rows do, since voucher_payload
  // shares the tuple with source_payload and tally_response. The queue's edit flow
  // writes only edit_state + created_at, so its echo carries no voucher_payload at
  // all. rowToEntry would then read an empty payload, blank the party/amount and
  // fall through to its purchase branch, dropping the row out of the Sale tab
  // until the next refresh. (History hits the same thing and re-fetches — see
  // _ingestPushedRow; the queue already has the row, so a merge is enough.)
  //
  // Realtime's column cache can also lag a freshly-added column, so an echo may
  // omit edit_state entirely and wipe the "under edit"/"invoice edited" tag.
  //
  // Returns null when the payload is gone and there's no prior copy to restore it
  // from: the row can't be classified at all, so drop the echo and let refresh()
  // reconcile it.
  Map<String, dynamic>? _restoreDroppedColumns(
    Map<String, dynamic> row,
    String entryId,
  ) {
    final exists = _entries.any((e) => e.id == entryId);
    final prior = exists ? _entries.firstWhere((e) => e.id == entryId) : null;
    final patched = Map<String, dynamic>.from(row);
    if (parsePayload(row['voucher_payload']).isEmpty) {
      final priorResult = prior?.scanResult;
      if (priorResult == null) return null;
      patched['voucher_payload'] = Map<String, dynamic>.from(priorResult)
        ..removeWhere((k, _) => k.startsWith('__'));
      patched['source_payload'] ??= priorResult['__source_payload'];
    }
    if (prior != null && !row.containsKey('edit_state')) {
      patched['edit_state'] = prior.editState.dbValue;
    }
    return patched;
  }

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
            if (isStockItemRow(row)) return;
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
            final entryId = 'supabase_${payload.newRecord['id']}';
            final row = _restoreDroppedColumns(payload.newRecord, entryId);
            if (row == null) return;
            if (isStockItemRow(row)) return;
            final newStatus = row['status'] as String?;
            // A row only leaves the live queue once it's actually pushed (it
            // moves to History). Every other status — pending/push_now/failed
            // AND any transient status the backend sets in between — keeps the
            // row visible, so a just-pushed voucher doesn't vanish and then
            // reappear on the next refresh.
            if (newStatus == 'pushed') {
              _entries = _entries.where((e) => e.id != entryId).toList();
              // The row is leaving the queue for History — remember its purchase
              // reference so a later re-upload is flagged "Already Pushed".
              final ref = _purchaseReferenceOf(row);
              if (ref.isNotEmpty) _pushedPurchaseReferences.add(ref);
            } else {
              final updated = rowToEntry(row);
              final exists = _entries.any((e) => e.id == entryId);
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
          .where((row) => !isStockItemRow(row))
          .map(rowToEntry)
          .toList();

      // Rebuild the pushed-purchase-reference set for the queue duplicate check.
      // Only voucher_payload is needed; parse + classify in Dart via the shared
      // helpers so the SALE/purchase rule stays in one place.
      final pushed = await Supabase.instance.client
          .from('push_queue')
          .select('voucher_payload')
          .eq('status', 'pushed');
      _pushedPurchaseReferences
        ..clear()
        ..addAll((pushed as List)
            .cast<Map<String, dynamic>>()
            .map(_purchaseReferenceOf)
            .where((ref) => ref.isNotEmpty));

      onEntriesChanged(List.of(_entries));
    } catch (e, st) {
      // A failure here leaves the visible queue empty/stale — surface it instead
      // of swallowing (cf. the push_queue column-drift incident).
      reportHandledError('supabase.push_queue.refresh', e, stackTrace: st);
    }
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
