import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/models.dart';
import 'core/seed_data.dart';
import 'screens/queue_screen.dart';
import 'screens/history_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/report_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/capture_type_dialog.dart';

class AccountantShell extends StatefulWidget {
  const AccountantShell({super.key});

  @override
  State<AccountantShell> createState() => _AccountantShellState();
}

class _AccountantShellState extends State<AccountantShell> {
  int _currentIndex = 0;
  int _queueTabIndex = 0;

  // Sale seed rows (stable)
  List<QueueEntry> _saleEntries = [];
  // Locally scanned PDFs (prepended on scan response)
  final List<QueueEntry> _localPurchaseEntries = [];
  // Live rows from push_queue Supabase table
  List<QueueEntry> _supabaseEntries = [];

  RealtimeChannel? _pushQueueChannel;

  final List<CapturedShot> _captures = <CapturedShot>[];
  TransactionType? _activeCaptureType;

  List<QueueEntry> get _allRows => [
        ..._localPurchaseEntries,
        ..._supabaseEntries,
        ..._saleEntries,
      ];

  @override
  void initState() {
    super.initState();
    _saleEntries = seedQueueEntries
        .where((e) => e.type == TransactionType.sale)
        .toList();
    _subscribeToPushQueue(); // unawaited — updates state when ready
  }

  @override
  void dispose() {
    _pushQueueChannel?.unsubscribe();
    super.dispose();
  }

  // ── Supabase realtime ────────────────────────────────────────────────────────

  static bool _isActiveStatus(String? status) =>
      status == 'pending' || status == 'push_now';

  Future<void> _subscribeToPushQueue() async {
    // 1. Initial fetch — only pending / push_now rows, newest first
    try {
      final response = await Supabase.instance.client
          .from('push_queue')
          .select('id, status, created_at, voucher_payload')
          .inFilter('status', ['pending', 'push_now'])
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _supabaseEntries = (response as List)
            .cast<Map<String, dynamic>>()
            .map(_rowToEntry)
            .toList();
      });
    } catch (_) {}

    // 2. Realtime channel — INSERT / UPDATE / DELETE
    _pushQueueChannel = Supabase.instance.client
        .channel('push_queue_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            if (!mounted) return;
            final row = payload.newRecord;
            if (!_isActiveStatus(row['status'] as String?)) return;
            setState(() {
              _supabaseEntries = [_rowToEntry(row), ..._supabaseEntries];
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            if (!mounted) return;
            final deletedId = payload.oldRecord['id']?.toString();
            if (deletedId == null) return;
            setState(() {
              _supabaseEntries = _supabaseEntries
                  .where((e) => e.id != 'supabase_$deletedId')
                  .toList();
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'push_queue',
          callback: (payload) {
            if (!mounted) return;
            final row = payload.newRecord;
            final newStatus = row['status'] as String?;
            final entryId = 'supabase_${row['id']}';
            if (_isActiveStatus(newStatus)) {
              // Update in place (or add if somehow missing)
              final updatedEntry = _rowToEntry(row);
              final exists = _supabaseEntries.any((e) => e.id == entryId);
              setState(() {
                _supabaseEntries = exists
                    ? _supabaseEntries
                        .map((e) => e.id == entryId ? updatedEntry : e)
                        .toList()
                    : [updatedEntry, ..._supabaseEntries];
              });
            } else {
              // Status changed to pushed/failed — remove from list
              setState(() {
                _supabaseEntries =
                    _supabaseEntries.where((e) => e.id != entryId).toList();
              });
            }
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

  QueueEntry _rowToEntry(Map<String, dynamic> row) {
    final payload = _parsePayload(row['voucher_payload']);

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
      dayLabel: _toDateLabel(createdAt),
      timeLabel: _toTimeLabel(createdAt),
      scanResult: {
        ...payload,
        '__row_id': row['id']?.toString() ?? '',
        '__status': row['status'] as String? ?? 'pending',
      },
    );
  }

  static String _toDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month]}';
  }

  static String _toTimeLabel(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  // ── Rows change handler ──────────────────────────────────────────────────────

  void _onRowsChanged(List<QueueEntry> rows) {
    setState(() {
      _saleEntries =
          rows.where((e) => e.type == TransactionType.sale).toList();
      _localPurchaseEntries
        ..clear()
        ..addAll(rows.where((e) => e.id.startsWith('purchase_scan_')));
      // Preserve checkbox / status changes made to Supabase rows
      final byId = {
        for (final e in rows.where((e) => e.id.startsWith('supabase_'))) e.id: e
      };
      _supabaseEntries =
          _supabaseEntries.map((e) => byId[e.id] ?? e).toList();
    });
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  Future<void> _onNavSelected(int index) async {
    if (index == 2) {
      await _openTaggedCameraFlow();
      return;
    }
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  Future<void> _openTaggedCameraFlow([TransactionType? preferredType]) async {
    final selectedType = preferredType ?? await _showCaptureTypeDialog();
    if (!mounted || selectedType == null) return;

    setState(() {
      _activeCaptureType = selectedType;
      _currentIndex = 2;
    });

    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (!isAndroid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document scanning is only available on Android.'),
        ),
      );
      return;
    }

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.pdf},
        mode: ScannerMode.full,
        pageLimit: 20,
        isGalleryImport: false,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      if (!mounted) return;

      final pdfPath = result.pdf?.uri;
      if (pdfPath == null || pdfPath.isEmpty) return;

      setState(() {
        _captures.add(
          CapturedShot(
            id: '${DateTime.now().microsecondsSinceEpoch}_$pdfPath',
            type: selectedType,
            path: pdfPath,
          ),
        );
      });

      if (selectedType == TransactionType.purchase) {
        await _uploadAndShowResult(pdfPath);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the document scanner. Check camera permission and try again.',
          ),
        ),
      );
    } finally {
      scanner.close();
    }
  }

  // ── Upload ───────────────────────────────────────────────────────────────────

  static const String _parseUrl =
      'https://magnolia-universe-specimen.ngrok-free.dev?type=purchase&company=K%20V%20ENTERPRISES';

  Future<void> _uploadAndShowResult(String pdfPath) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Your Purchase vouchers is being processed and will soon show up in Queue page',
        ),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final bytes = await File(pdfPath).readAsBytes();
      final response = await http.post(
        Uri.parse(_parseUrl),
        headers: {'Content-Type': 'application/pdf'},
        body: bytes,
      );

      if (!mounted) return;

      final parsed = jsonDecode(response.body) as Map<String, dynamic>;
      final header =
          (parsed['ocr'] as Map<String, dynamic>)['header']
              as Map<String, dynamic>;
      final vendorName =
          (header['vendor_name'] as String?) ?? 'Unknown Vendor';
      final invoiceTotal =
          (header['invoice_total'] as num?)?.toDouble() ?? 0.0;

      final now = DateTime.now();
      setState(() {
        _localPurchaseEntries.insert(
          0,
          QueueEntry(
            id: 'purchase_scan_${now.microsecondsSinceEpoch}',
            type: TransactionType.purchase,
            party: vendorName,
            amount: invoiceTotal,
            dayLabel: 'Today',
            timeLabel: _toTimeLabel(now),
            scanResult: parsed,
          ),
        );
        _currentIndex = 0;
        _queueTabIndex = 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<TransactionType?> _showCaptureTypeDialog() {
    return showDialog<TransactionType>(
      context: context,
      builder: (context) => const CaptureTypeDialog(),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        QueueScreen(
          currentIndex: _currentIndex,
          onNavSelected: _onNavSelected,
          rows: _allRows,
          onRowsChanged: _onRowsChanged,
          tabIndex: _queueTabIndex,
          onTabChanged: (i) => setState(() => _queueTabIndex = i),
        ),
        HistoryScreen(
          currentIndex: _currentIndex,
          onNavSelected: _onNavSelected,
        ),
        CameraScreen(
          currentIndex: _currentIndex,
          onNavSelected: _onNavSelected,
          captures: _captures,
          activeCaptureType: _activeCaptureType,
          onCaptureRequested: _openTaggedCameraFlow,
        ),
        ReportScreen(
          currentIndex: _currentIndex,
          onNavSelected: _onNavSelected,
        ),
        ProfileScreen(
          currentIndex: _currentIndex,
          onNavSelected: _onNavSelected,
        ),
      ],
    );
  }
}
