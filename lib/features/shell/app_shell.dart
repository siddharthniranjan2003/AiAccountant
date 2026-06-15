import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../../core/models.dart';
import '../../core/config.dart';
import '../../data/seed_data.dart';
import '../../data/push_queue_service.dart';
import '../../data/scan_inflight_service.dart';
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
  List<QueueEntry> _supabaseEntries = [];

  // The in-flight scan list lives in a process-level singleton (not here) so it
  // survives the shell being destroyed/recreated while the native scanner is in front.
  // We listen to it to repaint the "Processing…" count badge + timer.
  final ScanInFlightService _scanService = ScanInFlightService.instance;

  TransactionType get _activeQueueType =>
      _queueTabIndex == 0 ? TransactionType.sale : TransactionType.purchase;

  late final PushQueueService _pushQueueService;

  final List<CapturedShot> _captures = <CapturedShot>[];
  TransactionType? _activeCaptureType;

  List<QueueEntry> get _allRows => [
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
      // When a parsed invoice row lands, clear one "processing" scan of that type.
      onRowInserted: _scanService.notifyInvoiceArrived,
    );
    _pushQueueService.subscribe();

    // Repaint the count badge/timer whenever the processing set changes.
    _scanService.addListener(_onInFlightChanged);
  }

  @override
  void dispose() {
    _scanService.removeListener(_onInFlightChanged);
    _pushQueueService.unsubscribe();
    super.dispose();
  }

  void _onInFlightChanged() {
    if (mounted) setState(() {});
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
      // Only seed sale rows live here now; every scanned voucher comes from
      // Supabase, so keep the non-supabase sale rows and rebuild the rest.
      _saleEntries = rows
          .where((e) => e.type == TransactionType.sale && !e.id.startsWith('supabase_'))
          .toList();
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

      setState(() {
        _captures.add(CapturedShot(
          id: '${DateTime.now().microsecondsSinceEpoch}_$pdfPath',
          type: selectedType,
          path: pdfPath,
        ));
      });

      _enqueueScan(pdfPath, type: selectedType);
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

  static const String _purchaseParseUrl = Config.purchaseParseUrl;
  static const String _saleParseUrl = Config.saleParseUrl;

  // Hands the scanned PDF to the in-flight service, which fires its parse request
  // immediately and tracks it (driving the count badge + timer). The count drops and
  // the queue refreshes when each reply returns — all in the singleton, so it keeps
  // working even if this shell is destroyed/recreated while the next scan is in front.
  void _enqueueScan(String pdfPath, {required TransactionType type}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Your ${type.label} voucher is being processed…'),
        duration: const Duration(seconds: 2),
      ),
    );

    final url = type == TransactionType.sale ? _saleParseUrl : _purchaseParseUrl;
    _scanService.enqueue(type, pdfPath, url);
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
          loadingCount: _scanService.countFor(_activeQueueType),
          oldestLoadingStart: _scanService.oldestStartFor(_activeQueueType),
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
