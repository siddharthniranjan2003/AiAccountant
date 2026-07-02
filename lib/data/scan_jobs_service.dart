import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_reporter.dart';
import '../core/models.dart';
import 'push_queue_service.dart';

// One scan mirrored from a `scan_jobs` row. While `status == 'processing'` it is
// an in-flight scan (drives the "Processing…" badge). When the parsing service
// can't turn it into a voucher it flips the row to `status == 'failed'` (with a
// `reason` and the `pageCount` of stored images) — a "Garbage invoice" the app
// surfaces so the scan isn't silently lost. createdAt drives the timer ring / sort;
// the row id is the job_id (also the GCS key for the failed scan's page images).
class _ScanJob {
  _ScanJob(
    this.id,
    this.type,
    this.createdAt, {
    this.status = 'processing',
    this.reason,
    this.pageCount = 0,
  });

  final String id;
  final TransactionType type;
  final DateTime createdAt;
  final String status;
  final String? reason;
  final int pageCount;

  bool get isFailed => status == 'failed';
}

// Process-level singleton that mirrors the shared `scan_jobs` table over Supabase
// realtime, so the queue's "Processing…" badge + timer climb and drain on EVERY
// logged-in client — the scanning phone AND any open web session — not just the
// device that did the scan.
//
// The badge is a pure reflection of the table; no client decrements it:
//   +1  Mobile calls [startScan] the instant a scan is sent — it inserts a
//       scan_jobs row and returns its id (the job_id to pass to the parser). The
//       realtime INSERT echo makes the badge climb on every client.
//   -1  On success the parsing service DELETEs the row by id right after it
//       inserts the matching push_queue invoice row; the realtime DELETE echo
//       drains the badge on every client.
//   ✗  On failure (no party/stock match, unreadable, ingest down) the parsing
//       service instead UPDATEs the row to status='failed'; it leaves the badge
//       (no longer 'processing') and surfaces as a "Garbage invoice" via
//       [garbageEntries], which the user can open (image) and [dismiss] (delete).
// Living in the isolate (not a widget State) keeps the subscription alive while
// the native scanner is in front and the shell is torn down/recreated.
class ScanJobsService extends ChangeNotifier {
  ScanJobsService._();
  static final ScanJobsService instance = ScanJobsService._();

  // A processing row older than this is ignored, so a DELETE that never arrives
  // (e.g. the scanning device went offline before its invoice landed) can't wedge
  // the badge. Measured parse round-trip is ~105s; cold starts run longer. Failed
  // rows are EXEMPT — they persist until the user dismisses them.
  static const Duration _maxAge = Duration(seconds: 300);

  final List<_ScanJob> _jobs = [];
  RealtimeChannel? _channel;

  SupabaseClient get _db => Supabase.instance.client;

  // In-flight (processing) rows within the safety window — drives the badge/timer.
  Iterable<_ScanJob> get _processing {
    final cutoff = DateTime.now().subtract(_maxAge);
    return _jobs.where(
      (j) => j.status == 'processing' && j.createdAt.isAfter(cutoff),
    );
  }

  // Number of this type's scans still in flight (the count badge).
  int countFor(TransactionType type) =>
      _processing.where((j) => j.type == type).length;

  // Earliest send time among this type's in-flight scans; drives the timer ring.
  DateTime? oldestStartFor(TransactionType type) {
    DateTime? oldest;
    for (final job in _processing) {
      if (job.type != type) continue;
      if (oldest == null || job.createdAt.isBefore(oldest)) {
        oldest = job.createdAt;
      }
    }
    return oldest;
  }

  // Failed scans rendered as queue rows — a "Garbage invoice" entry per failed
  // job. Marked with `__garbage` (routes the tap to the image-only sheet) and
  // `__scan_job_id` / `__page_count` (the GCS image key + how many pages to show).
  // `__status: 'failed'` reuses the existing red row styling in QueueRowTile.
  List<QueueEntry> garbageEntries() {
    return _jobs.where((j) => j.isFailed).map((j) {
      return QueueEntry(
        id: 'garbage_${j.id}',
        type: j.type,
        party: 'Garbage invoice',
        amount: 0,
        dayLabel: PushQueueService.toDateLabel(j.createdAt),
        timeLabel: PushQueueService.toTimeLabel(j.createdAt),
        sortKey: j.createdAt.millisecondsSinceEpoch,
        scanResult: {
          '__garbage': true,
          '__status': 'failed',
          '__scan_job_id': j.id,
          '__page_count': j.pageCount,
          if (j.reason != null) '__reason': j.reason,
        },
      );
    }).toList();
  }

  // Start mirroring scan_jobs: initial fetch + realtime INSERT/UPDATE/DELETE.
  // Idempotent — safe to call again when the shell is recreated. Call after
  // Supabase is initialized (it is, from main() before runApp).
  Future<void> subscribe() async {
    // Always re-sync first — catches up anything realtime missed (e.g. a DELETE
    // or a fail-UPDATE that arrived while this client was backgrounded), so a
    // recreated shell never shows a stale badge or misses a garbage row.
    await _refresh();
    if (_channel != null) return; // channel already live; don't double-subscribe
    _channel = _db
        .channel('scan_jobs_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'scan_jobs',
          callback: (payload) => _add(payload.newRecord),
        )
        .onPostgresChanges(
          // A scan that failed to parse: the parser flips it to status='failed'.
          // newRecord is the full row (independent of replica identity), so we
          // just replace our copy — the processing→failed flip moves it from the
          // badge to the garbage list.
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'scan_jobs',
          callback: (payload) => _upsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'scan_jobs',
          callback: (payload) => _removeById(payload.oldRecord['id']?.toString()),
        )
        .subscribe();
    // Periodically expire stale PROCESSING rows so a missed DELETE can't stick the
    // badge. Failed rows are never swept here — they persist until dismissed.
    // Not stored: this singleton lives for the session, so it never needs cancel.
    Timer.periodic(const Duration(seconds: 5), (_) => _sweep());
  }

  // Re-fetch the tracked set. Realtime events (a DELETE, or the fail-UPDATE) can
  // be missed while the app/tab is backgrounded and its socket is suspended,
  // leaving a stale badge or a missing garbage row; call this on foreground.
  Future<void> resync() => _refresh();

  // Mobile only: record that a scan was just sent. Inserts a scan_jobs row and
  // returns its id to use as the parse request's job_id (so the parsing service
  // can delete this exact row when the invoice lands, or mark it failed). Returns
  // null on failure — the scan still proceeds; the badge just won't reflect it.
  Future<String?> startScan(TransactionType type) async {
    try {
      final row = await _db
          .from('scan_jobs')
          .insert({'type': type.name})
          .select('id, type, created_at, status, reason, page_count')
          .single();
      _add(row); // optimistic local add; the realtime echo is deduped by id
      return row['id']?.toString();
    } catch (e, st) {
      reportHandledError('supabase.scan_jobs.startScan', e,
          stackTrace: st, context: {'type': type.name});
      debugPrint('startScan insert failed: $e');
      return null;
    }
  }

  // Dismiss a "Garbage invoice": delete its scan_jobs row. The realtime DELETE
  // echo removes it from the queue on every client. Optimistic locally so the row
  // disappears immediately even if the network round-trip lags.
  Future<void> dismiss(String scanJobId) async {
    _removeById(scanJobId);
    try {
      await _db.from('scan_jobs').delete().eq('id', scanJobId);
    } catch (e, st) {
      reportHandledError('supabase.scan_jobs.dismiss', e,
          stackTrace: st, context: {'id': scanJobId});
    }
  }

  Future<void> _refresh() async {
    try {
      final cutoff =
          DateTime.now().toUtc().subtract(_maxAge).toIso8601String();
      // Fresh in-flight rows (created within the TTL) PLUS every failed row
      // regardless of age (garbage invoices persist until dismissed).
      final rows = await _db
          .from('scan_jobs')
          .select('id, type, created_at, status, reason, page_count')
          .or('status.eq.failed,created_at.gte.$cutoff');
      _jobs
        ..clear()
        ..addAll((rows as List).cast<Map<String, dynamic>>().map(_toJob));
      notifyListeners();
    } catch (e, st) {
      reportHandledError('supabase.scan_jobs.refresh', e, stackTrace: st);
    }
  }

  void _add(Map<String, dynamic> row) {
    final job = _toJob(row);
    if (_jobs.any((j) => j.id == job.id)) return; // dedupe optimistic vs echo
    _jobs.add(job);
    notifyListeners();
  }

  // Insert-or-replace by id (realtime UPDATE echo, e.g. processing→failed).
  void _upsert(Map<String, dynamic> row) {
    final job = _toJob(row);
    final index = _jobs.indexWhere((j) => j.id == job.id);
    if (index >= 0) {
      _jobs[index] = job;
    } else {
      _jobs.add(job);
    }
    notifyListeners();
  }

  void _removeById(String? id) {
    if (id == null) return;
    final before = _jobs.length;
    _jobs.removeWhere((j) => j.id == id);
    if (_jobs.length != before) notifyListeners();
  }

  void _sweep() {
    final cutoff = DateTime.now().subtract(_maxAge);
    final before = _jobs.length;
    // Only expire stale PROCESSING rows; failed rows persist until dismissed.
    _jobs.removeWhere(
      (j) => j.status == 'processing' && !j.createdAt.isAfter(cutoff),
    );
    if (_jobs.length != before) notifyListeners();
  }

  static _ScanJob _toJob(Map<String, dynamic> row) {
    final type = (row['type'] as String?) == 'sale'
        ? TransactionType.sale
        : TransactionType.purchase;
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now();
    return _ScanJob(
      row['id'].toString(),
      type,
      createdAt,
      status: (row['status'] as String?) ?? 'processing',
      reason: row['reason'] as String?,
      pageCount: (row['page_count'] as num?)?.toInt() ?? 0,
    );
  }
}
