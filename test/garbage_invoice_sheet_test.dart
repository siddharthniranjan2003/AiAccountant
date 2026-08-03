import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/features/queue/garbage_invoice_sheet.dart';

const _runpod = 'Server Side Error, Kindly Re Scan this image (RunPods)';
const _generic = "Couldn't read this invoice — please re-scan.";

// pageCount: 0 skips the image branch entirely, so nothing network-facing runs
// and the sheet pumps without Supabase or the API client.
Future<void> pumpSheet(WidgetTester tester, String? reason) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GarbageInvoiceSheet(
        scanJobId: 'job-1',
        pageCount: 0,
        reason: reason,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  // Verbatim from scan_jobs.reason — a RunPod outage, not an unreadable scan.
  // The default wording would send the user off re-photographing a good document.
  testWidgets('a RunPod failure names the outage', (tester) async {
    await pumpSheet(tester,
        '520 Server Error: <none> for url: https://api.runpod.ai/v2/vllm-l3ra5g9jipnoeu/run');

    expect(find.text(_runpod), findsOneWidget);
    expect(find.text(_generic), findsNothing);
  });

  // Why the match is on the host and not the full URL: the pod id changes every
  // time the endpoint is redeployed, and other 5xx/timeouts tell the same story.
  testWidgets('still matches after the endpoint is redeployed', (tester) async {
    await pumpSheet(tester,
        '500 Server Error: <none> for url: https://api.runpod.ai/v2/some-other-pod-id/run');

    expect(find.text(_runpod), findsOneWidget);
  });

  testWidgets('an unmatched party keeps the generic text', (tester) async {
    await pumpSheet(
        tester, 'No party_name matched in Supabase; cannot build a Sales voucher.');

    expect(find.text(_generic), findsOneWidget);
    expect(find.text(_runpod), findsNothing);
  });

  testWidgets('no reason at all keeps the generic text', (tester) async {
    await pumpSheet(tester, null);

    expect(find.text(_generic), findsOneWidget);
  });
}
