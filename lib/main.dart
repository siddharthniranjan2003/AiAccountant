import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

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
      theme: _buildTheme(),
      home: const AccountantShell(),
    );
  }
}

ThemeData _buildTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppPalette.ink,
    onPrimary: Colors.white,
    secondary: AppPalette.accent,
    onSecondary: Colors.white,
    tertiary: AppPalette.pen,
    onTertiary: Colors.white,
    error: AppPalette.accent,
    onError: Colors.white,
    surface: AppPalette.sheet,
    onSurface: AppPalette.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppPalette.paper,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: const TextStyle(
        color: AppPalette.ink,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleLarge: const TextStyle(
        color: AppPalette.ink,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: const TextStyle(
        color: AppPalette.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: const TextStyle(
        color: AppPalette.ink,
        fontSize: 14,
        height: 1.35,
      ),
      bodyMedium: const TextStyle(
        color: AppPalette.ink,
        fontSize: 13,
        height: 1.35,
      ),
      bodySmall: const TextStyle(
        color: AppPalette.inkSoft,
        fontSize: 11.5,
        height: 1.4,
      ),
      labelLarge: const TextStyle(
        color: AppPalette.ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: const TextStyle(
        color: AppPalette.inkSoft,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      labelSmall: const TextStyle(
        color: AppPalette.muted,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
    ),
  );
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

  Future<void> _openTaggedCameraFlow([TransactionType? preferredType]) async {
    final selectedType = preferredType ?? await _showCaptureTypeDialog();
    if (!mounted || selectedType == null) {
      return;
    }

    setState(() {
      _activeCaptureType = selectedType;
      _currentIndex = 2;
    });

    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (!isAndroid) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Document scanning is only available on Android.',
          ),
        ),
      );
      return;
    }

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: false,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      if (!mounted || result.images.isEmpty) {
        return;
      }

      setState(() {
        _captures.addAll(
          result.images.map(
            (path) => CapturedShot(
              id: '${DateTime.now().microsecondsSinceEpoch}_$path',
              type: selectedType,
              path: path,
            ),
          ),
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
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

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  int _tabIndex = 0;
  late List<QueueEntry> _rows;
  final List<ToastEntry> _toasts = <ToastEntry>[];

  @override
  void initState() {
    super.initState();
    _rows = List<QueueEntry>.from(seedQueueEntries);
  }

  TransactionType get _activeType =>
      _tabIndex == 0 ? TransactionType.sale : TransactionType.purchase;

  List<QueueEntry> get _visibleRows =>
      _rows.where((entry) => entry.type == _activeType).toList();

  int get _selectedCount => _visibleRows
      .where((entry) => entry.checked && entry.status != QueueStatus.done)
      .length;

  String _showToast(
    String message, {
    required ToastKind kind,
    Duration? autoDismiss,
  }) {
    final toast = ToastEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      message: message,
      kind: kind,
    );

    setState(() {
      _toasts.add(toast);
    });

    if (autoDismiss != null) {
      Future<void>.delayed(autoDismiss, () {
        if (!mounted) {
          return;
        }
        _dismissToast(toast.id);
      });
    }

    return toast.id;
  }

  void _dismissToast(String id) {
    setState(() {
      _toasts.removeWhere((toast) => toast.id == id);
    });
  }

  void _updateEntry(
    String id,
    QueueEntry Function(QueueEntry current) transform,
  ) {
    setState(() {
      _rows = _rows
          .map((entry) => entry.id == id ? transform(entry) : entry)
          .toList();
    });
  }

  Future<void> _openChallanSheet(QueueEntry entry) async {
    if (entry.status == QueueStatus.processing) {
      return;
    }

    final didConfirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppSpreadsheetSheet(
          fileName: 'challan_${_sheetSlug(entry.party)}.xlsx',
          toolbarItems: const ['File', 'Edit', 'View', 'Σ', '%'],
          columnLabels: const ['Item', 'HSN', 'Qty', 'Rate', 'GST%', 'Amount'],
          columnWidths: const [42, 220, 88, 70, 84, 78, 108],
          rows: buildChallanRows(entry.party),
          footerLeading: 'Sheet1 · 5 line items',
          footerTrailing: 'Σ ₹2,604.26',
          trailingAction: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppPalette.ink, width: 1.3),
              ),
            ),
            child: const Text('Done'),
          ),
        );
      },
    );

    if (didConfirm == true) {
      await _processSingleEntry(entry);
    }
  }

  Future<void> _processSingleEntry(QueueEntry entry) async {
    _updateEntry(
      entry.id,
      (current) => current.copyWith(
        checked: true,
        status: QueueStatus.processing,
      ),
    );

    final processingToast = _showToast(
      'Your ${entry.type.label.toLowerCase()} challan for ${entry.party} is being processed…',
      kind: ToastKind.processing,
    );

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) {
      return;
    }

    _dismissToast(processingToast);
    _updateEntry(
      entry.id,
      (current) => current.copyWith(
        checked: true,
        status: QueueStatus.done,
      ),
    );
    _showToast(
      '${entry.party} · ${entry.type.label.toLowerCase()} challan is done',
      kind: ToastKind.success,
      autoDismiss: const Duration(milliseconds: 2600),
    );
  }

  Future<void> _confirmSelected() async {
    final selectedIds = _visibleRows
        .where((entry) => entry.checked && entry.status == QueueStatus.pending)
        .map((entry) => entry.id)
        .toList();

    if (selectedIds.isEmpty) {
      return;
    }

    setState(() {
      _rows = _rows.map((entry) {
        if (selectedIds.contains(entry.id)) {
          return entry.copyWith(status: QueueStatus.processing, checked: true);
        }
        return entry;
      }).toList();
    });

    final processingToast = _showToast(
      'Confirming ${selectedIds.length} ${_activeType.label.toLowerCase()} challans…',
      kind: ToastKind.processing,
    );

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) {
      return;
    }

    _dismissToast(processingToast);
    setState(() {
      _rows = _rows.map((entry) {
        if (selectedIds.contains(entry.id)) {
          return entry.copyWith(status: QueueStatus.done, checked: true);
        }
        return entry;
      }).toList();
    });
    _showToast(
      '${selectedIds.length} ${_activeType.label.toLowerCase()} challans confirmed',
      kind: ToastKind.success,
      autoDismiss: const Duration(milliseconds: 2600),
    );
  }

  Map<String, List<QueueEntry>> _groupRows(List<QueueEntry> rows) {
    final groups = <String, List<QueueEntry>>{};
    for (final row in rows) {
      groups.putIfAbsent(row.dayLabel, () => <QueueEntry>[]).add(row);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groupedRows = _groupRows(_visibleRows);
    final serialLookup = <String, int>{
      for (int index = 0; index < _visibleRows.length; index++)
        _visibleRows[index].id: index + 1,
    };

    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      overlays: [
        if (_toasts.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: kBottomNavHeight + 12,
            child: ToastStack(toasts: _toasts),
          ),
      ],
      body: Column(
        children: [
          AppTopTabs(
            labels: const ['Sale', 'Purchase'],
            selectedIndex: _tabIndex,
            onSelected: (index) {
              setState(() {
                _tabIndex = index;
              });
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  const QueueTableHeader(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 18),
                      children: [
                        for (final group in groupedRows.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
                            child: Text(
                              group.key,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppPalette.ink,
                                width: 1.4,
                              ),
                            ),
                            child: Column(
                              children: [
                                for (int index = 0;
                                    index < group.value.length;
                                    index++)
                                  QueueRowTile(
                                    entry: group.value[index],
                                    isFirst: index == 0,
                                    serialNumber:
                                        serialLookup[group.value[index].id]!,
                                    onPartyTap:
                                        group.value[index].status ==
                                                QueueStatus.processing
                                            ? null
                                            : () => _openChallanSheet(
                                                  group.value[index],
                                                ),
                                    onCheckboxTap:
                                        group.value[index].status ==
                                                QueueStatus.done
                                            ? null
                                            : () => _updateEntry(
                                                  group.value[index].id,
                                                  (current) => current.copyWith(
                                                    checked: !current.checked,
                                                  ),
                                                ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _filterIndex = 0;

  @override
  Widget build(BuildContext context) {
    final visibleItems = switch (_filterIndex) {
      0 => seedHistoryEntries,
      1 => seedHistoryEntries
          .where((entry) => entry.type == TransactionType.sale)
          .toList(),
      _ => seedHistoryEntries
          .where((entry) => entry.type == TransactionType.purchase)
          .toList(),
    };

    final grouped = <String, List<HistoryEntry>>{};
    for (final entry in visibleItems) {
      grouped.putIfAbsent(entry.monthLabel, () => <HistoryEntry>[]).add(entry);
    }

    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      body: Column(
        children: [
          AppTopTabs(
            labels: const ['All', 'Sale', 'Purchase'],
            selectedIndex: _filterIndex,
            onSelected: (index) {
              setState(() {
                _filterIndex = index;
              });
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                for (final group in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                    child: Text(
                      group.key,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  for (final entry in group.value) ...[
                    HistoryCard(entry: entry),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
    required this.captures,
    required this.activeCaptureType,
    required this.onCaptureRequested,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;
  final List<CapturedShot> captures;
  final TransactionType? activeCaptureType;
  final Future<void> Function(TransactionType? preferredType)
      onCaptureRequested;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  Future<void> _openCaptureTray() async {
    if (widget.captures.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.44,
          child: Container(
            decoration: const BoxDecoration(
              color: AppPalette.sheet,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 56,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Row(
                    children: [
                      Text(
                        'Captured batch',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const Spacer(),
                      Text(
                        '${widget.captures.length} shots',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    itemCount: widget.captures.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.74,
                    ),
                    itemBuilder: (context, index) {
                      final shot = widget.captures[index];
                      final color = captureColorForType(
                        shot.type,
                        seedOffset: index,
                      );
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppPalette.ink,
                            width: 1.4,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              color.withOpacity(0.95),
                              AppPalette.ink,
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shot.path
                                  .split(RegExp(r'[\\/]'))
                                  .last
                                  .toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '${shot.type.label} receipt',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                  ),
                            ),
                            Text(
                              'Capture ${index + 1}',
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.white70,
                                      ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.18,
            colors: [
              Color(0xFF31353F),
              Color(0xFF171A20),
              Color(0xFF0D0F12),
            ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CameraOverlayBrackets(),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          if (widget.activeCaptureType != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white70,
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                '${widget.activeCaptureType!.label} batch',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 18),
                          Text(
                            widget.activeCaptureType == null
                                ? 'choose sale or purchase first'
                                : 'point at ${widget.activeCaptureType!.label.toLowerCase()} receipt',
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.1,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: _openCaptureTray,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      widget.captures.isEmpty
                                          ? Colors.white24
                                          : captureColorForType(
                                              widget.captures.last.type,
                                              seedOffset: widget.captures.length,
                                            ).withOpacity(0.95),
                                      Colors.black,
                                    ],
                                  ),
                                ),
                              ),
                              if (widget.captures.isNotEmpty)
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: AppPalette.accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.3,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${widget.captures.length}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              widget.onCaptureRequested(widget.activeCaptureType),
                          child: Container(
                            width: 82,
                            height: 82,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.94),
                                width: 2.2,
                              ),
                            ),
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.black87,
                                  width: 2.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => widget.onCaptureRequested(null),
                          child: Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white70,
                                width: 1.6,
                              ),
                            ),
                            child: Text(
                              '+',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _tabIndex = 0;
  String? _loadingCategoryKey;

  Future<void> _openReport(ReportCategory category) async {
    setState(() {
      _loadingCategoryKey = category.key;
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) {
      return;
    }

    setState(() {
      _loadingCategoryKey = null;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppSpreadsheetSheet(
          fileName: '/${category.key}.csv',
          toolbarItems: const ['File', 'Edit', 'View', 'Filter', 'Σ'],
          columnLabels: const [
            'stock_item',
            'sales_6m',
            'pur_1m',
            'stock_qty',
            'stock_₹',
            'scenario',
          ],
          columnWidths: const [42, 220, 88, 88, 96, 96, 140],
          rows: category.rows,
          footerLeading: category.footerMeta,
          footerTrailing: 'Σ ${category.footerSum}',
          trailingAction: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.ink,
              side: const BorderSide(color: AppPalette.ink, width: 1.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Close'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      body: Column(
        children: [
          AppTopTabs(
            labels: const ['Insights', 'Export'],
            selectedIndex: _tabIndex,
            onSelected: (index) {
              setState(() {
                _tabIndex = index;
              });
            },
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _tabIndex == 0
                  ? ListView.separated(
                      key: const ValueKey('insights'),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      itemCount: seedReportCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final category = seedReportCategories[index];
                        return ReportListItem(
                          category: category,
                          isLoading: _loadingCategoryKey == category.key,
                          onTap: () => _openReport(category),
                        );
                      },
                    )
                  : ListView(
                      key: const ValueKey('exports'),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      children: const [
                        ExportCard(
                          title: 'Monthly CSV pack',
                          subtitle:
                              'Bundle sales, purchases, and inventory deltas for a clean handoff to finance.',
                          icon: Icons.file_open_outlined,
                        ),
                        SizedBox(height: 10),
                        ExportCard(
                          title: 'GST workbook',
                          subtitle:
                              'Ready-to-review tax summary laid out as a workbook with filing checkpoints.',
                          icon: Icons.receipt_long_outlined,
                        ),
                        SizedBox(height: 10),
                        ExportCard(
                          title: 'Ledger snapshot',
                          subtitle:
                              'Structured export for external accountants and reconciliation workflows.',
                          icon: Icons.table_chart_outlined,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      currentIndex: currentIndex,
      onNavSelected: onNavSelected,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
        children: const [
          ProfileHeaderCard(),
          SizedBox(height: 14),
          SettingRow(label: 'Business details'),
          SizedBox(height: 6),
          SettingRow(label: 'Tax / GST settings'),
          SizedBox(height: 6),
          SettingRow(label: 'Currency & date'),
          SizedBox(height: 6),
          SettingRow(label: 'Backup & export'),
          SizedBox(height: 6),
          SettingRow(label: 'AI accuracy'),
          SizedBox(height: 6),
          SettingRow(label: 'Help & support'),
          SizedBox(height: 6),
          SettingRow(label: 'Sign out', destructive: true),
        ],
      ),
    );
  }
}

class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
    required this.body,
    this.stickyFooter,
    this.overlays = const <Widget>[],
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;
  final Widget body;
  final Widget? stickyFooter;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF9ED),
              Color(0xFFF1E7D3),
              AppPalette.paper,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.sheet,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: AppPalette.ink,
                      width: 1.8,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A141E3C),
                        offset: Offset(4, 6),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: PaperPainter(),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            Expanded(child: body),
                            if (stickyFooter != null) stickyFooter!,
                            AppBottomNav(
                              currentIndex: currentIndex,
                              onSelected: onNavSelected,
                            ),
                          ],
                        ),
                        ...overlays,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppTopTabs extends StatelessWidget {
  const AppTopTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppPalette.ink,
            width: 1.3,
          ),
        ),
      ),
      child: Row(
        children: [
          for (int index = 0; index < labels.length; index++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(index),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: index == labels.length - 1
                          ? BorderSide.none
                          : const BorderSide(
                              color: AppPalette.ink,
                              width: 1.2,
                            ),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labels[index],
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: index == selectedIndex
                                      ? AppPalette.ink
                                      : AppPalette.inkSoft,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: index == selectedIndex ? 56 : 24,
                        height: 3,
                        decoration: BoxDecoration(
                          color: index == selectedIndex
                              ? AppPalette.ink
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kBottomNavHeight,
      decoration: BoxDecoration(
        color: AppPalette.paper.withOpacity(0.92),
        border: const Border(
          top: BorderSide(
            color: AppPalette.ink,
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          for (int index = 0; index < bottomNavItems.length; index++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(index),
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    if (index == currentIndex && index != 2)
                      Positioned(
                        top: 0,
                        left: 22,
                        right: 22,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppPalette.ink,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Transform.translate(
                            offset: Offset(0, index == 2 ? -18 : 0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              width: index == 2 ? 52 : 40,
                              height: index == 2 ? 52 : 40,
                              margin: EdgeInsets.only(
                                bottom: index == 2 ? 5 : 2,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: index == 2
                                    ? currentIndex == index
                                        ? AppPalette.accent
                                        : AppPalette.sheet
                                    : currentIndex == index
                                        ? AppPalette.accent2.withOpacity(0.45)
                                        : Colors.transparent,
                                border: Border.all(
                                  color: AppPalette.ink,
                                  width: index == 2 ? 1.7 : 1.4,
                                ),
                              ),
                              child: Icon(
                                bottomNavItems[index].icon,
                                size: index == 2 ? 26 : 20,
                                color: index == 2 && currentIndex == index
                                    ? Colors.white
                                    : AppPalette.ink,
                              ),
                            ),
                          ),
                          Text(
                            bottomNavItems[index].label,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: currentIndex == index
                                          ? AppPalette.ink
                                          : AppPalette.inkSoft,
                                      fontWeight: currentIndex == index
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class QueueTableHeader extends StatelessWidget {
  const QueueTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppPalette.ink,
          fontWeight: FontWeight.w800,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.gridHeader.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.ink, width: 1.3),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 22,
            child: TextCell(text: '#', align: TextAlign.left, isHeader: true),
          ),
          SizedBox(width: 8),
          Expanded(
            child: TextCell(text: 'Party', align: TextAlign.left, isHeader: true),
          ),
          SizedBox(
            width: 76,
            child:
                TextCell(text: 'Amount', align: TextAlign.right, isHeader: true),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: TextCell(text: 'Time', align: TextAlign.right, isHeader: true),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 22,
            child: TextCell(text: '', align: TextAlign.center, isHeader: true),
          ),
        ],
      ),
    );
  }
}

class QueueRowTile extends StatelessWidget {
  const QueueRowTile({
    super.key,
    required this.entry,
    required this.serialNumber,
    required this.isFirst,
    required this.onPartyTap,
    required this.onCheckboxTap,
  });

  final QueueEntry entry;
  final int serialNumber;
  final bool isFirst;
  final VoidCallback? onPartyTap;
  final VoidCallback? onCheckboxTap;

  @override
  Widget build(BuildContext context) {
    final isDone = entry.status == QueueStatus.done;
    final isProcessing = entry.status == QueueStatus.processing;
    final opacity = entry.status == QueueStatus.pending ? 1.0 : 0.56;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: isFirst
                ? BorderSide.none
                : BorderSide(
                    color: AppPalette.line.withOpacity(0.8),
                    width: 1,
                  ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$serialNumber',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.muted,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: onPartyTap,
                  child: Text(
                    entry.party,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDone ? AppPalette.muted : AppPalette.pen,
                          fontWeight: FontWeight.w800,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : TextDecoration.underline,
                        ),
                  ),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  formatCurrency(entry.amount),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Text(
                  entry.timeLabel,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 22,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkCheckbox(
                    value: entry.checked,
                    success: isDone,
                    processing: isProcessing,
                    onTap: onCheckboxTap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QueueBulkBar extends StatelessWidget {
  const QueueBulkBar({
    super.key,
    required this.selectedCount,
    required this.onConfirm,
  });

  final int selectedCount;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kBulkBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0D3),
        border: const Border(
          top: BorderSide(color: AppPalette.ink, width: 1.2),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$selectedCount selected',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppPalette.line,
              disabledForegroundColor: AppPalette.inkSoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppPalette.ink, width: 1.3),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class InkCheckbox extends StatelessWidget {
  const InkCheckbox({
    super.key,
    required this.value,
    required this.success,
    required this.processing,
    this.onTap,
  });

  final bool value;
  final bool success;
  final bool processing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: success
              ? AppPalette.success.withOpacity(0.16)
              : value
                  ? AppPalette.accent2.withOpacity(0.26)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: success
                ? AppPalette.success
                : value
                    ? AppPalette.accent
                    : AppPalette.ink,
            width: 1.4,
          ),
        ),
        alignment: Alignment.center,
        child: processing
            ? const SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppPalette.accent,
                ),
              )
            : value
                ? Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: success ? AppPalette.success : AppPalette.accent,
                  )
                : null,
      ),
    );
  }
}

class ToastStack extends StatelessWidget {
  const ToastStack({
    super.key,
    required this.toasts,
  });

  final List<ToastEntry> toasts;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final toast in toasts) ...[
          ToastCard(toast: toast),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class ToastCard extends StatelessWidget {
  const ToastCard({
    super.key,
    required this.toast,
  });

  final ToastEntry toast;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = switch (toast.kind) {
      ToastKind.processing => AppPalette.ink,
      ToastKind.success => AppPalette.success,
      ToastKind.info => AppPalette.pen,
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 8,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            if (toast.kind == ToastKind.processing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.white,
                ),
              )
            else
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.white,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                toast.message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.entry,
  });

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isSale = entry.type == TransactionType.sale;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppPalette.ink,
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppPalette.ink, width: 1.3),
              color: isSale
                  ? AppPalette.accent2.withOpacity(0.35)
                  : AppPalette.line.withOpacity(0.35),
            ),
            child: Text(
              isSale ? 'S' : 'P',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.party,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.type.label} · ${entry.dateLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '${isSale ? '+' : '−'}${formatCurrency(entry.amount)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isSale ? AppPalette.success : AppPalette.accent,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class ReportListItem extends StatelessWidget {
  const ReportListItem({
    super.key,
    required this.category,
    required this.isLoading,
    required this.onTap,
  });

  final ReportCategory category;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppPalette.line.withOpacity(0.9),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '/${category.key}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppPalette.ink,
                          letterSpacing: 0.1,
                        ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: AppPalette.accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.emoji,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppPalette.inkSoft,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExportCard extends StatelessWidget {
  const ExportCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppPalette.ink,
          width: 1.4,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppPalette.accent2.withOpacity(0.35),
              border: Border.all(color: AppPalette.ink, width: 1.2),
            ),
            child: Icon(icon, color: AppPalette.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSoft,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppPalette.ink,
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppPalette.accent2.withOpacity(0.4),
              border: Border.all(color: AppPalette.ink, width: 1.4),
            ),
            child: Text(
              'RK',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ravi Kumar',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ravi@store.in · GST 27ABCDE1234F1Z5',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSoft,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.destructive = false,
  });

  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: destructive ? AppPalette.accent : AppPalette.ink,
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: destructive ? AppPalette.accent : AppPalette.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: destructive ? AppPalette.accent : AppPalette.inkSoft,
          ),
        ],
      ),
    );
  }
}

class AppSpreadsheetSheet extends StatelessWidget {
  const AppSpreadsheetSheet({
    super.key,
    required this.fileName,
    required this.toolbarItems,
    required this.columnLabels,
    required this.columnWidths,
    required this.rows,
    required this.footerLeading,
    required this.footerTrailing,
    required this.trailingAction,
  });

  final String fileName;
  final List<String> toolbarItems;
  final List<String> columnLabels;
  final List<double> columnWidths;
  final List<List<String>> rows;
  final String footerLeading;
  final String footerTrailing;
  final Widget trailingAction;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: const BoxDecoration(
          color: AppPalette.sheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 56,
              height: 4,
              decoration: BoxDecoration(
                color: AppPalette.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppPalette.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailingAction,
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.gridHeader.withOpacity(0.6),
                border: Border(
                  top: BorderSide(
                    color: AppPalette.ink.withOpacity(0.18),
                  ),
                  bottom: BorderSide(
                    color: AppPalette.ink.withOpacity(0.18),
                  ),
                ),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final item in toolbarItems)
                    Text(
                      item,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppPalette.inkSoft,
                          ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SpreadsheetGrid(
                    columnLabels: columnLabels,
                    columnWidths: columnWidths,
                    rows: rows,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppPalette.ink,
                    width: 1.2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      footerLeading,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    footerTrailing,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpreadsheetGrid extends StatelessWidget {
  const SpreadsheetGrid({
    super.key,
    required this.columnLabels,
    required this.columnWidths,
    required this.rows,
  });

  final List<String> columnLabels;
  final List<double> columnWidths;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final letters = List<String>.generate(
      columnLabels.length,
      (index) => String.fromCharCode(65 + index),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppPalette.ink,
          width: 1.3,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpreadsheetGridRow(
            cells: [''] + letters,
            widths: columnWidths,
            isHeader: true,
            backgroundColor: AppPalette.gridHeader,
          ),
          SpreadsheetGridRow(
            cells: [''] + columnLabels,
            widths: columnWidths,
            isHeader: true,
            backgroundColor: AppPalette.gridHeader.withOpacity(0.58),
          ),
          for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
            SpreadsheetGridRow(
              cells: ['${rowIndex + 1}', ...rows[rowIndex]],
              widths: columnWidths,
              isHeader: false,
              backgroundColor:
                  rowIndex.isEven ? Colors.white : AppPalette.paper.withOpacity(0.5),
            ),
        ],
      ),
    );
  }
}

class SpreadsheetGridRow extends StatelessWidget {
  const SpreadsheetGridRow({
    super.key,
    required this.cells,
    required this.widths,
    required this.isHeader,
    required this.backgroundColor,
  });

  final List<String> cells;
  final List<double> widths;
  final bool isHeader;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: AppPalette.ink.withOpacity(0.18),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          for (int index = 0; index < cells.length; index++)
            Container(
              width: widths[index],
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  right: index == cells.length - 1
                      ? BorderSide.none
                      : BorderSide(
                          color: AppPalette.ink.withOpacity(0.14),
                        ),
                ),
              ),
              child: Text(
                cells[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: index == 0 ? TextAlign.center : TextAlign.left,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cells[index].isEmpty
                          ? AppPalette.muted
                          : AppPalette.ink,
                      fontWeight: isHeader ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class CameraOverlayBrackets extends StatelessWidget {
  const CameraOverlayBrackets({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        CameraCorner(top: 72, left: 28),
        CameraCorner(top: 72, right: 28, rightSide: true),
        CameraCorner(bottom: 132, left: 28, bottomSide: true),
        CameraCorner(
          bottom: 132,
          right: 28,
          rightSide: true,
          bottomSide: true,
        ),
      ],
    );
  }
}

class CameraCorner extends StatelessWidget {
  const CameraCorner({
    super.key,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.rightSide = false,
    this.bottomSide = false,
  });

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final bool rightSide;
  final bool bottomSide;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: SizedBox(
        width: 26,
        height: 26,
        child: CustomPaint(
          painter: CornerPainter(
            rightSide: rightSide,
            bottomSide: bottomSide,
          ),
        ),
      ),
    );
  }
}

class TextCell extends StatelessWidget {
  const TextCell({
    super.key,
    required this.text,
    this.align = TextAlign.left,
    this.isHeader = false,
  });

  final String text;
  final TextAlign align;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.ink,
            fontWeight: isHeader ? FontWeight.w800 : FontWeight.w700,
          ),
    );
  }
}

class PaperPainter extends CustomPainter {
  const PaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppPalette.line.withOpacity(0.12)
      ..strokeWidth = 1;

    for (double y = 24; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CornerPainter extends CustomPainter {
  const CornerPainter({
    required this.rightSide,
    required this.bottomSide,
  });

  final bool rightSide;
  final bool bottomSide;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final horizontalStart = Offset(rightSide ? size.width : 0, bottomSide ? size.height : 0);
    final horizontalEnd = Offset(rightSide ? size.width - 18 : 18, bottomSide ? size.height : 0);
    final verticalStart = Offset(rightSide ? size.width : 0, bottomSide ? size.height : 0);
    final verticalEnd = Offset(rightSide ? size.width : 0, bottomSide ? size.height - 18 : 18);

    canvas.drawLine(horizontalStart, horizontalEnd, paint);
    canvas.drawLine(verticalStart, verticalEnd, paint);
  }

  @override
  bool shouldRepaint(covariant CornerPainter oldDelegate) {
    return oldDelegate.rightSide != rightSide ||
        oldDelegate.bottomSide != bottomSide;
  }
}

class CaptureTypeDialog extends StatelessWidget {
  const CaptureTypeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: AppPalette.sheet,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: AppPalette.ink,
            width: 1.6,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'What is this?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: CaptureTypeOption(
                    label: 'Sale',
                    onTap: () =>
                        Navigator.of(context).pop(TransactionType.sale),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: CaptureTypeOption(
                    label: 'Purchase',
                    onTap: () =>
                        Navigator.of(context).pop(TransactionType.purchase),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.inkSoft,
                    ),
                children: const [
                  TextSpan(
                    text: 'Then ',
                    style: TextStyle(
                      color: AppPalette.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(text: 'camera opens, already tagged'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CaptureTypeOption extends StatelessWidget {
  const CaptureTypeOption({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 122,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppPalette.ink,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppPalette.accent2.withOpacity(0.35),
                border: Border.all(
                  color: AppPalette.ink,
                  width: 1.2,
                ),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: AppPalette.accent,
                size: 18,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  });

  final String id;
  final TransactionType type;
  final String party;
  final double amount;
  final String dayLabel;
  final String timeLabel;
  final bool checked;
  final QueueStatus status;

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
  });

  final String party;
  final TransactionType type;
  final double amount;
  final String dateLabel;
  final String monthLabel;
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
  });

  final String key;
  final String emoji;
  final String description;
  final List<List<String>> rows;
  final String footerMeta;
  final String footerSum;
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

class AppPalette {
  static const paper = Color(0xFFF6F1E6);
  static const sheet = Color(0xFFFDF9F0);
  static const ink = Color(0xFF16181D);
  static const inkSoft = Color(0xFF3A3F49);
  static const pen = Color(0xFF1F3A8A);
  static const accent = Color(0xFFD94F3A);
  static const accent2 = Color(0xFFF2C94C);
  static const muted = Color(0xFF8A8576);
  static const line = Color(0xFFB9C8DF);
  static const success = Color(0xFF1D7A3A);
  static const gridHeader = Color(0xFFE9EEF5);

  const AppPalette._();
}

const double kBottomNavHeight = 78;
const double kBulkBarHeight = 58;

const List<BottomNavItemData> bottomNavItems = [
  BottomNavItemData(label: 'Queue', icon: Icons.view_agenda_rounded),
  BottomNavItemData(label: 'History', icon: Icons.history_rounded),
  BottomNavItemData(label: 'Camera', icon: Icons.camera_alt_rounded),
  BottomNavItemData(label: 'Report', icon: Icons.insert_chart_outlined_rounded),
  BottomNavItemData(label: 'Profile', icon: Icons.person_outline_rounded),
];

const List<Color> capturePalette = [
  Color(0xFFD94F3A),
  Color(0xFFF2C94C),
  Color(0xFF7FA6F6),
  Color(0xFF55A780),
  Color(0xFFCA7C57),
];

const List<QueueEntry> seedQueueEntries = [
  QueueEntry(
    id: 'sale_abc',
    type: TransactionType.sale,
    party: 'ABC Traders',
    amount: 100,
    dayLabel: 'Today',
    timeLabel: '10:14',
    checked: true,
  ),
  QueueEntry(
    id: 'sale_def',
    type: TransactionType.sale,
    party: 'Delta Fasteners',
    amount: 200,
    dayLabel: 'Today',
    timeLabel: '11:02',
    checked: true,
  ),
  QueueEntry(
    id: 'sale_xyz',
    type: TransactionType.sale,
    party: 'XYZ Mart',
    amount: 300,
    dayLabel: 'Yesterday',
    timeLabel: '17:48',
  ),
  QueueEntry(
    id: 'sale_mno',
    type: TransactionType.sale,
    party: 'MNO Supply',
    amount: 450,
    dayLabel: 'Yesterday',
    timeLabel: '14:21',
  ),
  QueueEntry(
    id: 'purchase_krishna',
    type: TransactionType.purchase,
    party: 'Krishna Steels',
    amount: 980,
    dayLabel: 'Today',
    timeLabel: '09:40',
    checked: true,
  ),
  QueueEntry(
    id: 'purchase_gupta',
    type: TransactionType.purchase,
    party: 'Gupta Tools',
    amount: 1240,
    dayLabel: 'Today',
    timeLabel: '12:26',
  ),
  QueueEntry(
    id: 'purchase_anchor',
    type: TransactionType.purchase,
    party: 'Anchor Components',
    amount: 575,
    dayLabel: 'Yesterday',
    timeLabel: '16:05',
  ),
  QueueEntry(
    id: 'purchase_metro',
    type: TransactionType.purchase,
    party: 'Metro Bearings',
    amount: 860,
    dayLabel: 'Yesterday',
    timeLabel: '14:55',
  ),
];

const List<HistoryEntry> seedHistoryEntries = [
  HistoryEntry(
    party: 'ABC Traders',
    type: TransactionType.sale,
    amount: 100,
    dateLabel: '05 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'Delta Fasteners',
    type: TransactionType.purchase,
    amount: 200,
    dateLabel: '04 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'XYZ Mart',
    type: TransactionType.sale,
    amount: 300,
    dateLabel: '04 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'MNO Supply',
    type: TransactionType.purchase,
    amount: 450,
    dateLabel: '02 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'Prime Hardware',
    type: TransactionType.sale,
    amount: 520,
    dateLabel: '28 Apr',
    monthLabel: 'April 2026',
  ),
];

const List<ReportCategory> seedReportCategories = [
  ReportCategory(
    key: 'act_now',
    emoji: '🚨',
    description:
        'Items at risk of lost sales. Reorder immediately or within days. Highest revenue impact.',
    rows: [
      ['Allen Bolt 10×100', '188', '34', '9', '₹14,580', 'Reorder now'],
      ['AG-4 6mm Bear', '122', '20', '6', '₹8,960', '3 day cover'],
      ['Adjustable Wrench', '48', '11', '2', '₹3,220', 'Stockout risk'],
      ['Aerosol-OS', '74', '18', '5', '₹5,410', 'Cash tied, moving'],
    ],
    footerMeta: '2,140 rows · sorted by ₹ impact',
    footerSum: '₹32,170',
  ),
  ReportCategory(
    key: 'hero_sku_health',
    emoji: '🏆',
    description:
        'Top-performing items driving revenue. Protect at all costs. Never let them stock out.',
    rows: [
      ['Cutting Disc G80', '342', '44', '31', '₹48,920', 'Healthy'],
      ['Hex Bolt Pack', '301', '51', '22', '₹32,410', 'Watch lead time'],
      ['Industrial Drill Bit', '228', '29', '17', '₹24,800', 'Healthy'],
      ['Bearing Kit Pro', '174', '19', '11', '₹18,320', 'Watch demand'],
    ],
    footerMeta: '482 rows · sorted by sales velocity',
    footerSum: '₹124,450',
  ),
  ReportCategory(
    key: 'dead_capital',
    emoji: '💀',
    description:
        'Capital locked with zero or negative returns. Liquidate, write off, or audit. Sort by ₹ value.',
    rows: [
      ['Legacy Washer 14mm', '0', '15', '182', '₹12,640', 'No sales'],
      ['Drill Stand Basic', '2', '7', '44', '₹9,460', 'Exit candidate'],
      ['Masking Tape XL', '1', '6', '51', '₹4,920', 'Slow mover'],
      ['Bracket Set L', '0', '8', '27', '₹3,410', 'Audit lot'],
    ],
    footerMeta: '191 rows · sorted by dead capital',
    footerSum: '₹30,430',
  ),
  ReportCategory(
    key: 'buying_mistakes',
    emoji: '⚠️',
    description:
        'Purchasing happened without sales justification. Stop the bleed. Review buyer decisions.',
    rows: [
      ['Ceramic Wheel Red', '1', '12', '71', '₹10,220', 'No demand match'],
      ['Glue Cartridge X', '3', '19', '88', '₹7,740', 'Overbought'],
      ['Saw Blade 14"', '4', '14', '33', '₹6,590', 'Weak turns'],
      ['Dust Mask Bulk', '2', '18', '62', '₹5,860', 'Review policy'],
    ],
    footerMeta: '87 rows · sorted by mismatch score',
    footerSum: '₹30,410',
  ),
  ReportCategory(
    key: 'wind_down',
    emoji: '🪟',
    description:
        'Items clearing out by intent or neglect. Track days-to-clear. Recommit or exit cleanly.',
    rows: [
      ['Valve Spanner 9"', '14', '0', '8', '₹2,940', 'Clear in 12 days'],
      ['Allen Key Mini', '8', '0', '5', '₹820', 'Last batch'],
      ['Fast Cure Resin', '6', '0', '11', '₹1,630', 'Watch expiry'],
      ['Panel Clip Black', '5', '0', '7', '₹640', 'Clear channel'],
    ],
    footerMeta: '53 rows · sorted by exit timeline',
    footerSum: '₹6,030',
  ),
  ReportCategory(
    key: 'risk_watch',
    emoji: '👀',
    description:
        'Needs monitoring but not emergency action. Seasonal demand check. Cash flow exposure.',
    rows: [
      ['Monsoon Sealant', '28', '6', '14', '₹3,900', 'Seasonal'],
      ['Tile Spacer', '37', '8', '22', '₹2,810', 'Margin drift'],
      ['Paint Roller Pro', '24', '5', '9', '₹1,580', 'Demand noisy'],
      ['Protective Gloves', '61', '12', '31', '₹5,260', 'Watch price'],
    ],
    footerMeta: '612 rows · monitoring set',
    footerSum: '₹13,550',
  ),
  ReportCategory(
    key: 'full_portfolio_health',
    emoji: '📊',
    description:
        'Complete sorted view. Health score 1–100. Sort ascending to find worst items first.',
    rows: [
      ['Allen Bolt 10×100', '188', '34', '9', '₹14,580', '91'],
      ['Legacy Washer 14mm', '0', '15', '182', '₹12,640', '18'],
      ['Cutting Disc G80', '342', '44', '31', '₹48,920', '95'],
      ['Glue Cartridge X', '3', '19', '88', '₹7,740', '29'],
    ],
    footerMeta: '4,802 rows · all items ranked',
    footerSum: '₹83,880',
  ),
];

List<List<String>> buildChallanRows(String party) {
  final partyCode = party.split(' ').first.toUpperCase();
  return [
    ['$partyCode Bolt 10×100', '7318', '12', '8.50', '18', '120.36'],
    ['AG-4 6mm Bear', '6804', '25', '14.20', '18', '418.90'],
    ['Adjustable Wrench 12"', '8204', '3', '340.00', '18', '1,203.60'],
    ['Alkon Disc 5" G80', '6804', '10', '22.00', '18', '259.60'],
    ['Aerosol-OS', '3808', '6', '85.00', '18', '601.80'],
    ['', '', '', '', '', ''],
    ['', '', '', '', '', ''],
    ['', '', '', '', '', ''],
  ];
}

String _sheetSlug(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

String formatCurrency(num amount) {
  final hasDecimals = amount != amount.roundToDouble();
  return '₹${amount.toStringAsFixed(hasDecimals ? 2 : 0)}';
}

Color captureColorForType(TransactionType type, {int seedOffset = 0}) {
  final colors = type == TransactionType.sale
      ? const [
          Color(0xFFD94F3A),
          Color(0xFFF2C94C),
          Color(0xFFCA7C57),
        ]
      : const [
          Color(0xFF5B7AE5),
          Color(0xFF55A780),
          Color(0xFF7FA6F6),
        ];
  return colors[seedOffset % colors.length];
}
