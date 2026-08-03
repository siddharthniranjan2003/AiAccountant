import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../data/scan_jobs_service.dart';
import '../../services/api_client.dart';

// Bottom sheet for a "Garbage invoice" — a scan that failed to parse into a
// voucher. Shows only the scanned page image(s), fetched by the scan_jobs id via
// the id-agnostic GET /push-queue/:id/image/:page route, with a delete icon below
// to dismiss it (deletes the scan_jobs row, draining the row on every client).
class GarbageInvoiceSheet extends StatefulWidget {
  const GarbageInvoiceSheet({
    super.key,
    required this.scanJobId,
    required this.pageCount,
    this.reason,
  });

  final String scanJobId;
  final int pageCount;

  /// The parser's `scan_jobs.reason` for this failure, when it wrote one. Picks
  /// the sheet's subtitle — see [_GarbageInvoiceSheetState._subtitle].
  final String? reason;

  @override
  State<GarbageInvoiceSheet> createState() => _GarbageInvoiceSheetState();
}

class _GarbageInvoiceSheetState extends State<GarbageInvoiceSheet> {
  // Memoize per-page fetches so a scroll back doesn't re-download.
  final Map<int, Future<Uint8List>> _pageFutures = {};

  static const _runpodMessage =
      'Server Side Error, Kindly Re Scan this image (RunPods)';
  static const _defaultMessage = "Couldn't read this invoice — please re-scan.";

  // A RunPod failure means the inference endpoint was down, not that the scan
  // was unreadable — the default wording sends the user off re-photographing a
  // perfectly good document. Matched on the host and not the full URL: the pod
  // id changes whenever the endpoint is redeployed, and a 500 or a timeout from
  // the same service is the same story as the 520.
  String get _subtitle => (widget.reason ?? '').toLowerCase().contains('runpod')
      ? _runpodMessage
      : _defaultMessage;

  Future<Uint8List> _loadPage(int page) {
    return _pageFutures.putIfAbsent(
      page,
      () => ApiClient.getBytes(
        '/api/sync/push-queue/${widget.scanJobId}/image/$page',
      ),
    );
  }

  void _delete() {
    ScanJobsService.instance.dismiss(widget.scanJobId);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final hasImages = widget.pageCount > 0;
    return Container(
      height: height * 0.9,
      decoration: BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppPalette.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Garbage invoice',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppPalette.accent,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: hasImages
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        // Cap the page image to 45% of the sheet width, centered.
                        final imageWidth = constraints.maxWidth * 0.45;
                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (var page = 0; page < widget.pageCount; page++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Center(
                                  child: SizedBox(
                                    width: imageWidth,
                                    child: _GarbagePage(future: _loadPage(page)),
                                  ),
                                ),
                              ),
                            Center(
                              child: SizedBox(
                                width: imageWidth,
                                child: const _ScanTips(),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : Center(
                      child: Text(
                        'No image available',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppPalette.muted,
                            ),
                      ),
                    ),
            ),
            // Delete icon below the image.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: IconButton(
                onPressed: _delete,
                iconSize: 30,
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppPalette.accent,
                tooltip: 'Delete',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GarbagePage extends StatelessWidget {
  const _GarbagePage({required this.future});
  final Future<Uint8List> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 360,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const SizedBox(
            height: 120,
            child: Center(child: Text("Couldn't load this page.")),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snapshot.data!,
            fit: BoxFit.fitWidth,
            width: double.infinity,
          ),
        );
      },
    );
  }
}

// Scanning guidance shown below the failed scan image.
class _ScanTips extends StatelessWidget {
  const _ScanTips();

  static const _tips = [
    'Place the invoice on a flat, well-lit surface.',
    'Fit the whole invoice in the frame, including all edges.',
    'Hold the camera steady to avoid blur, glare, and shadows.',
    'Keep the paper flat and straight — no folds or tilt.',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tips',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.lightbulb_rounded, size: 18, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text(
                'for better scan',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in _tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 8),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppPalette.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppPalette.muted,
                            fontWeight: FontWeight.w600,
                          ),
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
