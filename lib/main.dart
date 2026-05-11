import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import 'core/theme.dart';
import 'core/models.dart';
import 'screens/queue_screen.dart';
import 'screens/history_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/report_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/capture_type_dialog.dart';

void main() {
  runApp(const AccountantApp());
}

class AccountantApp extends StatelessWidget {
  const AccountantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Accountant',
      theme: buildAppTheme(),
      home: const AccountantShell(),
    );
  }
}

class AccountantShell extends StatefulWidget {
  const AccountantShell({super.key});

  @override
  State<AccountantShell> createState() => _AccountantShellState();
}

class _AccountantShellState extends State<AccountantShell> {
  int _currentIndex = 0;
  final List<CapturedShot> _captures = <CapturedShot>[];
  TransactionType? _activeCaptureType;

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

  Future<void> _openTaggedCameraFlow(
      [TransactionType? preferredType]) async {
    final selectedType =
        preferredType ?? await _showCaptureTypeDialog();
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
          content: Text(
              'Document scanning is only available on Android.'),
        ),
      );
      return;
    }

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.pdf},
        mode: ScannerMode.full,
        pageLimit: 1,
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

  Future<TransactionType?> _showCaptureTypeDialog() {
    return showDialog<TransactionType>(
      context: context,
      builder: (context) => const CaptureTypeDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        QueueScreen(
          currentIndex: _currentIndex,
          onNavSelected: _onNavSelected,
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
