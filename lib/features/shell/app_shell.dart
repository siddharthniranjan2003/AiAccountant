import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../core/models.dart';
import '../../core/config.dart';
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
  List<QueueEntry> _supabaseEntries = [];

  // Parse requests currently in flight. Each scan registers a job while its
  // HTTP request runs and removes it on settle (success or error). Drives the
  // consolidated "Processing…" row (count badge + timer) at the top of the
  // queue. Lives here (above the IndexedStack) so jobs survive tab navigation
  // and back-to-back sending — multiple can be in flight at once.
  final List<_ScanJob> _jobs = [];

  TransactionType get _activeQueueType =>
      _queueTabIndex == 0 ? TransactionType.sale : TransactionType.purchase;

  int _loadingCountFor(TransactionType type) =>
      _jobs.where((j) => j.type == type).length;

  // Earliest start time among in-flight jobs of this type; drives the timer
  // ring (oldest = worst-case wait). Null when none are running.
  DateTime? _oldestStartFor(TransactionType type) {
    DateTime? oldest;
    for (final job in _jobs) {
      if (job.type != type) continue;
      if (oldest == null || job.startedAt.isBefore(oldest)) {
        oldest = job.startedAt;
      }
    }
    return oldest;
  }

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

  static const String _purchaseParseUrl = Config.purchaseParseUrl;
  static const String _saleParseUrl = Config.saleParseUrl;

  Future<void> _uploadAndShowResult(
    String pdfPath, {
    Uint8List? imageBytes,
    required TransactionType type,
  }) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Your ${type.label} voucher is being processed…'),
        duration: const Duration(seconds: 2),
      ),
    );

    final url = type == TransactionType.sale ? _saleParseUrl : _purchaseParseUrl;
    final future = _parseDocument(pdfPath, url);

    // Fire-and-forget: the parse runs in the background and is tracked by a
    // job (drives the queue's count + timer). No blocking modal is opened, so
    // the user can immediately scan and send the next PDF — multiple requests
    // run concurrently. The parsed voucher arrives as a queue row via Supabase
    // realtime; tapping that row opens the detail sheet for review.
    _trackScanJob(type, future);
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

  // Registers an in-flight job (shown as the "Processing…" count + timer in the
  // matching queue tab) while the parse request runs, removing it when the
  // request settles — success or error (Option A: tied to the HTTP request, not
  // the realtime row). Each job is independent, so one slow/failed PDF never
  // stalls the others. The parsed voucher arrives as a queue row via realtime;
  // a failed parse just clears its slot and shows a quiet snackbar.
  Future<void> _trackScanJob(TransactionType type, Future<dynamic> future) async {
    final job = _ScanJob(type, DateTime.now());
    setState(() => _jobs.add(job));
    var failed = false;
    try {
      await future;
    } catch (_) {
      failed = true;
    } finally {
      if (mounted) {
        setState(() => _jobs.remove(job));
        if (failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('A ${type.label.toLowerCase()} document couldn\'t be processed.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
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
          onRefresh: _pushQueueService.refresh,
          tabIndex: _queueTabIndex,
          onTabChanged: (i) => setState(() => _queueTabIndex = i),
          loadingCount: _loadingCountFor(_activeQueueType),
          oldestLoadingStart: _oldestStartFor(_activeQueueType),
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

// A single in-flight parse request. Identity (not value) distinguishes jobs, so
// removing one on settle never removes a sibling with the same start time.
class _ScanJob {
  _ScanJob(this.type, this.startedAt);

  final TransactionType type;
  final DateTime startedAt;
}
