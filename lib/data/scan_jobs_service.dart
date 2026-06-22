import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models.dart';

// One scan that has been sent and whose parsed invoice has not yet landed,
// mirrored from a `scan_jobs` row. createdAt drives the timer ring; the row id
// is the job_id the parsing service deletes on when the invoice arrives.
class _ScanJob {
  _ScanJob(this.id, this.type, this.createdAt);

  final String id;
  final TransactionType type;
  final DateTime createdAt;
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
//   -1  The parsing service DELETEs the row by id right after it inserts the
//       matching push_queue invoice row. The realtime DELETE echo drains the
//       badge on every client.
// Living in the isolate (not a widget State) keeps the subscription alive while
// the native scanner is in front and the shell is torn down/recreated.
class ScanJobsService extends ChangeNotifier {
  ScanJobsService._();
  static final ScanJobsService instance = ScanJobsService._();

  // A row older than this is ignored, so a DELETE that never arrives (e.g. the
  // scanning device went offline before its invoice landed) can't wedge the
  // badge. Measured parse round-trip is ~105s; cold starts run longer.
  static const Duration _maxAge = Duration(seconds: 300);

  final List<_ScanJob> _jobs = [];
  RealtimeChannel? _channel;

  SupabaseClient get _db => Supabase.instance.client;

  // Live rows only — drops anything past the safety window.
  Iterable<_ScanJob> get _fresh {
    final cutoff = DateTime.now().subtract(_maxAge);
    return _jobs.where((j) => j.createdAt.isAfter(cutoff));
  }

  // Number of this type's scans still in flight (the count badge).
  int countFor(TransactionType type) =>
      _fresh.where((j) => j.type == type).length;

  // Earliest send time among this type's in-flight scans; drives the timer ring.
  DateTime? oldestStartFor(TransactionType type) {
    DateTime? oldest;
    for (final job in _fresh) {
      if (job.type != type) continue;
      if (oldest == null || job.createdAt.isBefore(oldest)) {
        oldest = job.createdAt;
      }
    }
    return oldest;
  }

  // Start mirroring scan_jobs: initial fetch + realtime INSERT/DELETE. Idempotent
  // — safe to call again when the shell is recreated. Call after Supabase is
  // initialized (it is, from main() before runApp).
  Future<void> subscribe() async {
    // Always re-sync first — catches up anything realtime missed (e.g. a DELETE
    // that arrived while this client was backgrounded), so a recreated shell
    // never shows a stale badge.
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
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'scan_jobs',
          callback: (payload) => _removeById(payload.oldRecord['id']?.toString()),
        )
        .subscribe();
    // Periodically expire stale rows so a missed DELETE can't stick the badge.
    // Not stored: this singleton lives for the session, so it never needs cancel.
    Timer.periodic(const Duration(seconds: 5), (_) => _sweep());
  }

  // Re-fetch the in-flight set. Realtime events (notably the parsing service's
  // DELETE) can be missed while the app/tab is backgrounded and its socket is
  // suspended, leaving a stale badge; call this on return to the foreground.
  Future<void> resync() => _refresh();

  // Mobile only: record that a scan was just sent. Inserts a scan_jobs row and
  // returns its id to use as the parse request's job_id (so the parsing service
  // can delete this exact row when the invoice lands). Returns null on failure —
  // the scan still proceeds; the badge just won't reflect it for that scan.
  Future<String?> startScan(TransactionType type) async {
    try {
      final row = await _db
          .from('scan_jobs')
          .insert({'type': type.name})
          .select('id, type, created_at')
          .single();
      _add(row); // optimistic local add; the realtime echo is deduped by id
      return row['id']?.toString();
    } catch (e) {
      debugPrint('startScan insert failed: $e');
      return null;
    }
  }

  Future<void> _refresh() async {
    try {
      final cutoff =
          DateTime.now().toUtc().subtract(_maxAge).toIso8601String();
      final rows = await _db
          .from('scan_jobs')
          .select('id, type, created_at')
          .gte('created_at', cutoff);
      _jobs
        ..clear()
        ..addAll((rows as List).cast<Map<String, dynamic>>().map(_toJob));
      notifyListeners();
    } catch (_) {}
  }

  void _add(Map<String, dynamic> row) {
    final job = _toJob(row);
    if (_jobs.any((j) => j.id == job.id)) return; // dedupe optimistic vs echo
    _jobs.add(job);
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
    _jobs.removeWhere((j) => !j.createdAt.isAfter(cutoff));
    if (_jobs.length != before) notifyListeners();
  }

  static _ScanJob _toJob(Map<String, dynamic> row) {
    final type = (row['type'] as String?) == 'sale'
        ? TransactionType.sale
        : TransactionType.purchase;
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now();
    return _ScanJob(row['id'].toString(), type, createdAt);
  }
}
