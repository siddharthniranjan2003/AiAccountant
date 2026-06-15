import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';

// One scan that has been sent and whose parsed invoice has not yet shown up in the
// queue. enqueuedAt drives the timer ring; safetyTimer is a fallback that clears the
// job if its invoice never arrives. Identity (not value) distinguishes jobs.
class ScanJob {
  ScanJob(this.type, this.pdfPath, this.url, this.enqueuedAt);

  final TransactionType type;
  final String pdfPath;
  final String url;
  final DateTime enqueuedAt;
  Timer? safetyTimer;
}

// Process-level singleton that tracks scans that are "processing" — sent to the parse
// backend but whose invoice has not yet appeared in the queue. It lives in the Dart
// isolate (not a widget State) so the count survives the shell being recreated while
// the native scanner is in front.
//
// IMPORTANT: a job is cleared when its parsed invoice ROW arrives via Supabase realtime
// (notifyInvoiceArrived) — NOT when the parse HTTP reply returns. The HTTP reply comes
// back (or errors/drops) seconds before the invoice actually lands, so using it would
// drop the count too early (and is not what "decrease the count when the invoice shows"
// means). Sending still fires the HTTP request to trigger the backend, but its result
// does not move the count.
class ScanInFlightService extends ChangeNotifier {
  ScanInFlightService._();
  static final ScanInFlightService instance = ScanInFlightService._();

  // Fallback: if no invoice row ever arrives for a sent scan (parse produced nothing,
  // wrong status, etc.), drop it after this so the badge can't stay stuck. Measured
  // parse round-trip is ~105s and cold starts run longer, so this is generous enough
  // not to fire before a real invoice lands.
  static const Duration _maxPending = Duration(seconds: 300);

  final List<ScanJob> _pending = [];

  // Number of this type's scans still waiting for their invoice (the count badge).
  int countFor(TransactionType type) =>
      _pending.where((j) => j.type == type).length;

  // Earliest send time among this type's pending scans; drives the timer ring. Null
  // when none are pending.
  DateTime? oldestStartFor(TransactionType type) {
    DateTime? oldest;
    for (final job in _pending) {
      if (job.type != type) continue;
      if (oldest == null || job.enqueuedAt.isBefore(oldest)) {
        oldest = job.enqueuedAt;
      }
    }
    return oldest;
  }

  // Marks a scan as processing (count +1) and fires its parse request immediately.
  void enqueue(TransactionType type, String pdfPath, String url) {
    final job = ScanJob(type, pdfPath, url, DateTime.now());
    job.safetyTimer = Timer(_maxPending, () => _remove(job));
    _pending.add(job);
    notifyListeners();
    _send(job);
  }

  // Called when a parsed invoice row of [type] lands in the queue (realtime INSERT).
  // Clears the oldest pending scan of that type (count -1). This is the signal that
  // drives the count down.
  void notifyInvoiceArrived(TransactionType type) {
    final index = _pending.indexWhere((j) => j.type == type);
    if (index == -1) return;
    final job = _pending.removeAt(index);
    job.safetyTimer?.cancel();
    notifyListeners();
  }

  void _remove(ScanJob job) {
    if (_pending.remove(job)) {
      job.safetyTimer?.cancel();
      notifyListeners();
    }
  }

  // Sends the PDF to the parse backend to trigger the parse. The reply does NOT move
  // the count (the invoice row arriving does); failures are logged for visibility. The
  // timeout just stops a hung connection from leaking.
  Future<void> _send(ScanJob job) async {
    try {
      await _parseDocument(job.pdfPath, job.url)
          .timeout(const Duration(seconds: 300));
    } catch (e) {
      debugPrint('Parse send failed (${job.type.label}): $e');
    }
  }

  Future<Map<String, dynamic>> _parseDocument(String pdfPath, String url) async {
    final bytes = await File(pdfPath).readAsBytes();
    final response = await http.post(
      Uri.parse(url),
      headers: const {'Content-Type': 'application/pdf'},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _ParseException('HTTP ${response.statusCode}', _bodySnippet(response.body));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw _ParseException('unexpected response shape', decoded.runtimeType.toString());
    }
    return decoded;
  }

  static String _bodySnippet(String body) {
    final trimmed = body.trim();
    return trimmed.length <= 200 ? trimmed : '${trimmed.substring(0, 200)}…';
  }
}

// Raised when the parse endpoint returns a non-2xx status or a body that isn't a JSON
// object. Carries the reason + a short body snippet for logging.
class _ParseException implements Exception {
  _ParseException(this.reason, this.detail);

  final String reason;
  final String detail;

  @override
  String toString() => 'ParseException($reason): $detail';
}
