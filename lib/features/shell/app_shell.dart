import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../core/models.dart';
import '../../data/seed_data.dart';
import '../../data/push_queue_service.dart';
import '../queue/queue_screen.dart';
import '../queue/voucher_detail_sheet.dart';
import '../history/history_screen.dart';
import '../camera/camera_screen.dart';
import '../report/report_screen.dart';
import '../profile/profile_screen.dart';
import '../camera/capture_type_dialog.dart';

class AccountantShell extends StatefulWidget {
  const AccountantShell({super.key});

  @override
  State<AccountantShell> createState() => _AccountantShellState();
}

class _AccountantShellState extends State<AccountantShell> {
  int _currentIndex = 0;
  int _queueTabIndex = 0;

  List<QueueEntry> _saleEntries = [];
  final List<QueueEntry> _localPurchaseEntries = [];
  List<QueueEntry> _supabaseEntries = [];

  late final PushQueueService _pushQueueService;

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

    _pushQueueService = PushQueueService(
      onEntriesChanged: _onSupabaseEntriesChanged,
    );
    _pushQueueService.subscribe();
  }

  @override
  void dispose() {
    _pushQueueService.unsubscribe();
    super.dispose();
  }

  void _onSupabaseEntriesChanged(List<QueueEntry> freshFromDb) {
    if (!mounted) return;
    setState(() {
      final existingById = {for (final e in _supabaseEntries) e.id: e};
      _supabaseEntries = freshFromDb.map((newEntry) {
        final existing = existingById[newEntry.id];
        if (existing == null) return newEntry;
        return newEntry.copyWith(checked: existing.checked, status: existing.status);
      }).toList();
    });
  }

  void _onRowsChanged(List<QueueEntry> rows) {
    setState(() {
      // Supabase sale rows live in _supabaseEntries; keep only seed + scanned
      // sale rows here so they aren't double-counted in _allRows.
      _saleEntries = rows
          .where((e) => e.type == TransactionType.sale && !e.id.startsWith('supabase_'))
          .toList();
      _localPurchaseEntries
        ..clear()
        ..addAll(rows.where((e) => e.id.startsWith('purchase_scan_')));
      // Rebuild from the incoming rows so a local discard actually drops the
      // row; the next realtime event or refresh re-adds it from Supabase.
      _supabaseEntries =
          rows.where((e) => e.id.startsWith('supabase_')).toList();
    });
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  Future<void> _onNavSelected(int index) async {
    if (index == 2) {
      await _openTaggedCameraFlow();
      return;
    }
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  Future<void> _openTaggedCameraFlow([TransactionType? preferredType]) async {
    final selectedType = preferredType ?? await _showCaptureTypeDialog();
    if (!mounted || selectedType == null) return;

    _activeCaptureType = selectedType;

    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document scanning is only available on Android.')),
      );
      return;
    }

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg, DocumentFormat.pdf},
        mode: ScannerMode.full,
        pageLimit: 20,
        isGalleryImport: true,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      if (!mounted) return;

      final pdfPath = result.pdf?.uri;
      if (pdfPath == null || pdfPath.isEmpty) return;

      // Keep the first page as a JPEG preview for the Image tab.
      Uint8List? imageBytes;
      final images = result.images;
      if (images != null && images.isNotEmpty) {
        try {
          imageBytes = await File(images.first).readAsBytes();
        } catch (_) {}
      }

      setState(() {
        _captures.add(CapturedShot(
          id: '${DateTime.now().microsecondsSinceEpoch}_$pdfPath',
          type: selectedType,
          path: pdfPath,
        ));
      });

      await _uploadAndShowResult(pdfPath, imageBytes: imageBytes, type: selectedType);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the document scanner. Check camera permission and try again.')),
      );
    } finally {
      scanner.close();
    }
  }

  // ── Upload ───────────────────────────────────────────────────────────────────

  static const String _purchaseParseUrl =
      'https://tallybridge-parsing-950406969086.asia-south1.run.app/docstrange?purchase=all&source=runpod';
  static const String _saleParseUrl =
      'https://tallybridge-parsing-950406969086.asia-south1.run.app/?type=sale&push=queue';

  Future<void> _uploadAndShowResult(
    String pdfPath, {
    Uint8List? imageBytes,
    required TransactionType type,
  }) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Your ${type.label} voucher is being processed…'),
        duration: const Duration(seconds: 3),
      ),
    );

    final url = type == TransactionType.sale ? _saleParseUrl : _purchaseParseUrl;
    final future = _parseDocument(pdfPath, url);

    // Open the detail card immediately — the scanned image shows right away and
    // Summary/JSON fill in once parsing completes (mirrors dev_aiaccountant).
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoucherDetailSheet(
        pendingPayload: future,
        imageBytes: imageBytes,
      ),
    ));

    try {
      final parsed = await future;
      if (!mounted) return;

      // duplicacy: bool, { is_duplicate } (vlm), or { invoice_exists } (docstrange).
      // The sheet shows its own duplicate dialog, so here we just skip insertion.
      final duplicacyRaw = parsed['duplicacy'];
      final isDuplicate = duplicacyRaw == true ||
          (duplicacyRaw is Map &&
              (duplicacyRaw['is_duplicate'] == true ||
                  duplicacyRaw['invoice_exists'] == true));
      if (isDuplicate) return;

      // Prefer the voucher_payload (final, master-matched) for the row label.
      // Sales return it as sale_voucher_payload instead.
      final voucher = (parsed['voucher_payload'] as Map?)?.cast<String, dynamic>() ??
          (parsed['sale_voucher_payload'] as Map?)?.cast<String, dynamic>();
      final ocrBlock = (parsed['parsed'] ?? parsed['ocr']) as Map?;
      final header = ((ocrBlock ?? {})['header'] as Map?)?.cast<String, dynamic>() ?? {};
      final vendorName = (parsed['party_name'] as String?) ??
          (voucher?['party_name'] as String?) ??
          (header['vendor_name'] as String?) ??
          'Unknown Vendor';
      final ledgerEntries =
          (voucher?['ledger_entries'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final invoiceTotal = ledgerEntries.isNotEmpty
          ? ledgerEntries
              .map((e) => (e['amount'] as num?)?.toDouble().abs() ?? 0.0)
              .reduce((a, b) => a >= b ? a : b)
          : (header['invoice_total'] as num?)?.toDouble() ?? 0.0;

      final now = DateTime.now();
      final isSale = type == TransactionType.sale;
      final entry = QueueEntry(
        id: '${isSale ? 'sale' : 'purchase'}_scan_${now.microsecondsSinceEpoch}',
        type: type,
        party: vendorName,
        amount: invoiceTotal,
        dayLabel: 'Today',
        timeLabel: PushQueueService.toTimeLabel(now),
        scanResult: parsed,
        imageBytes: imageBytes,
      );
      setState(() {
        if (isSale) {
          _saleEntries.insert(0, entry);
          _queueTabIndex = 0;
        } else {
          _localPurchaseEntries.insert(0, entry);
          _queueTabIndex = 1;
        }
        _currentIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Future<Map<String, dynamic>> _parseDocument(String pdfPath, String url) async {
    final bytes = await File(pdfPath).readAsBytes();
    final response = await http.post(
      Uri.parse(url),
      headers: const {'Content-Type': 'application/pdf'},
      body: bytes,
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
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
          onRefresh: _pushQueueService.refresh,
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
