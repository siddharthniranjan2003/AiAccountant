import 'dart:typed_data';

import 'package:flutter/material.dart';

enum TransactionType { sale, purchase }

extension TransactionTypeLabel on TransactionType {
  String get label => this == TransactionType.sale ? 'Sale' : 'Purchase';
}

enum QueueStatus { pending, processing, done }

// Lifecycle marker for a row whose voucher was touched in the detail sheet.
// `underEdit`  → sheet closed while still mid-edit (changes not saved).
// `edited`     → edits were saved back to the row.
// Persisted in push_queue.edit_state so the tag survives a cold start and shows
// on every client; rowToEntry reads it back. The queue also keeps a short-lived
// local overlay, only so the tag appears instantly before the realtime echo lands.
enum QueueEditState {
  none,
  underEdit,
  edited;

  // Serialized form stored in the push_queue.edit_state column. `none` ⇒ NULL
  // (the column is cleared, e.g. on a Revert).
  String? get dbValue => switch (this) {
        QueueEditState.none => null,
        QueueEditState.underEdit => 'under_edit',
        QueueEditState.edited => 'edited',
      };

  static QueueEditState fromDb(String? raw) => switch (raw) {
        'under_edit' => QueueEditState.underEdit,
        'edited' => QueueEditState.edited,
        _ => QueueEditState.none,
      };
}

enum ToastKind { processing, success, info }

@immutable
class QueueEntry {
  const QueueEntry({
    required this.id,
    required this.type,
    required this.party,
    required this.amount,
    required this.dayLabel,
    required this.timeLabel,
    this.sortKey = 0,
    this.checked = false,
    this.status = QueueStatus.pending,
    this.scanResult,
    this.editState = QueueEditState.none,
    this.imageBytes,
  });

  final String id;
  final TransactionType type;
  final String party;
  final double amount;
  final String dayLabel;
  final String timeLabel;
  // Epoch millis of created_at; used to sort the queue newest-first. 0 = unknown.
  final int sortKey;
  final bool checked;
  final QueueStatus status;
  final Map<String, dynamic>? scanResult;
  final QueueEditState editState;
  final Uint8List? imageBytes;

  // True when the backend has flagged this voucher as already present in
  // TallyPrime (voucher_payload.invoice_exists). Tolerant of bool or string.
  bool get invoiceExists {
    final v = scanResult?['invoice_exists'];
    return v == true || v == 'true';
  }

  // Invoice number to surface under the party name. Prefer `reference` (the
  // reliable supplier invoice number on live data); `voucher_number` is a
  // blank/unreliable fallback. Null when neither is present.
  String? get invoiceNumber {
    final ref = (scanResult?['reference'] as String?)?.trim();
    if (ref != null && ref.isNotEmpty) return ref;
    final vno = (scanResult?['voucher_number'] as String?)?.trim();
    if (vno != null && vno.isNotEmpty) return vno;
    return null;
  }

  QueueEntry copyWith({
    bool? checked,
    QueueStatus? status,
    QueueEditState? editState,
  }) {
    return QueueEntry(
      id: id,
      type: type,
      party: party,
      amount: amount,
      dayLabel: dayLabel,
      timeLabel: timeLabel,
      sortKey: sortKey,
      checked: checked ?? this.checked,
      status: status ?? this.status,
      scanResult: scanResult,
      editState: editState ?? this.editState,
      imageBytes: imageBytes,
    );
  }
}

@immutable
class ToastEntry {
  const ToastEntry({
    required this.id,
    required this.message,
    required this.kind,
  });

  final String id;
  final String message;
  final ToastKind kind;
}

@immutable
class CapturedShot {
  const CapturedShot({
    required this.id,
    required this.type,
    required this.path,
  });

  final String id;
  final TransactionType type;
  final String path;
}

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.party,
    required this.type,
    required this.amount,
    required this.dateLabel,
    required this.monthLabel,
    this.sortKey = 0,
    this.rowId = '',
  });

  final String party;
  final TransactionType type;
  final double amount;
  final String dateLabel;
  final String monthLabel;
  final int sortKey;
  final String rowId;
}

@immutable
class ReportCategory {
  const ReportCategory({
    required this.key,
    required this.emoji,
    required this.description,
    required this.rows,
    required this.footerMeta,
    required this.footerSum,
    this.reportId,
  });

  final String key;
  final String emoji;
  final String description;
  final List<List<String>> rows;
  final String footerMeta;
  final String footerSum;
  // Backend report ID (R1–R7). When set, data is fetched live from the API.
  final String? reportId;
}

@immutable
class BottomNavItemData {
  const BottomNavItemData({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}
