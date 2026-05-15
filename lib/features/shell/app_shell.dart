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
      _saleEntries = rows.where((e) => e.type == TransactionType.sale).toList();
      _localPurchaseEntries
        ..clear()
        ..addAll(rows.where((e) => e.id.startsWith('purchase_scan_')));
      final byId = {
        for (final e in rows.where((e) => e.id.startsWith('supabase_'))) e.id: e
      };
      _supabaseEntries = _supabaseEntries.map((e) => byId[e.id] ?? e).toList();
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

    setState(() {
      _activeCaptureType = selectedType;
      _currentIndex = 2;
    });

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
        _captures.add(CapturedShot(
          id: '${DateTime.now().microsecondsSinceEpoch}_$pdfPath',
          type: selectedType,
          path: pdfPath,
        ));
      });

      if (selectedType == TransactionType.purchase) {
        await _uploadAndShowResult(pdfPath);
      }
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

  static const String _parseUrl =
      'https://magnolia-universe-specimen.ngrok-free.dev?type=purchase&company=K%20V%20ENTERPRISES';

  Future<void> _uploadAndShowResult(String pdfPath) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your Purchase vouchers is being processed and will soon show up in Queue page'),
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
      final header = (parsed['ocr'] as Map<String, dynamic>)['header'] as Map<String, dynamic>;
      final vendorName = (header['vendor_name'] as String?) ?? 'Unknown Vendor';
      final invoiceTotal = (header['invoice_total'] as num?)?.toDouble() ?? 0.0;

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
            timeLabel: PushQueueService.toTimeLabel(now),
            scanResult: parsed,
          ),
        );
        _currentIndex = 0;
        _queueTabIndex = 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
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
