import 'package:flutter/material.dart';

enum TransactionType { sale, purchase }

extension TransactionTypeLabel on TransactionType {
  String get label => this == TransactionType.sale ? 'Sale' : 'Purchase';
}

enum QueueStatus { pending, processing, done }

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
    this.checked = false,
    this.status = QueueStatus.pending,
    this.scanResult,
  });

  final String id;
  final TransactionType type;
  final String party;
  final double amount;
  final String dayLabel;
  final String timeLabel;
  final bool checked;
  final QueueStatus status;
  final Map<String, dynamic>? scanResult;

  QueueEntry copyWith({
    bool? checked,
    QueueStatus? status,
  }) {
    return QueueEntry(
      id: id,
      type: type,
      party: party,
      amount: amount,
      dayLabel: dayLabel,
      timeLabel: timeLabel,
      checked: checked ?? this.checked,
      status: status ?? this.status,
      scanResult: scanResult,
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
