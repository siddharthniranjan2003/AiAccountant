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
  });

  final String scanJobId;
  final int pageCount;

  @override
  State<GarbageInvoiceSheet> createState() => _GarbageInvoiceSheetState();
}

class _GarbageInvoiceSheetState extends State<GarbageInvoiceSheet> {
  // Memoize per-page fetches so a scroll back doesn't re-download.
  final Map<int, Future<Uint8List>> _pageFutures = {};

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
      decoration: const BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              "Couldn't read this invoice — please re-scan.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: hasImages
                  ? ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: widget.pageCount,
                      itemBuilder: (context, page) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _GarbagePage(future: _loadPage(page)),
                      ),
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
