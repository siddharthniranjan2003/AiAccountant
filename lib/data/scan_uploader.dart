import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Sends a scanned PDF to the parse backend to trigger parsing. Mobile-only (the
// only platform that scans). Fire-and-forget: the reply does NOT move the badge
// — the badge climbs on the scan_jobs INSERT (see ScanJobsService.startScan) and
// drains on the parsing service's scan_jobs DELETE when the invoice lands. The
// HTTP reply comes back (or errors/drops) before the invoice actually lands, so
// it's an unreliable signal; we just log failures. The timeout stops a hung
// connection from leaking.
//
// This is a top-level function (not tied to a widget) so the in-flight upload
// runs to completion even if the shell is destroyed/recreated while the next
// scan's native scanner is in front.
Future<void> sendScanToParser(String pdfPath, String url) async {
  try {
    final bytes = await File(pdfPath).readAsBytes();
    final response = await http
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/pdf'},
          body: bytes,
        )
        .timeout(const Duration(seconds: 300));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('Parse send failed: HTTP ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Parse send failed: $e');
  }
}
