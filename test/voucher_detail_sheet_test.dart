import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/site_config.dart';
import 'package:aiaccountant/data/stock_items_cache.dart';
import 'package:aiaccountant/features/queue/voucher_detail_sheet.dart';

// A pending row auto-opens in edit mode (initState), and having no __row_id
// means the sheet never touches Supabase. Values are chosen so WIDGET A's Qty
// cell is the only editable field whose text is exactly '2'.
const _payload = <String, dynamic>{
  '__status': 'pending',
  'party_name': 'ACME TRADERS',
  'voucher_type': 'GST SALE',
  'voucher_number': 'SALE-1',
  'date': '2026-07-01',
  'items': [
    {'stock_item_name': 'WIDGET A', 'quantity': 2, 'rate': 10, 'amount': 20},
    {'stock_item_name': 'WIDGET B', 'quantity': 1, 'rate': 8, 'amount': 8},
  ],
  'ledger_entries': <Map<String, dynamic>>[],
};

void main() {
  testWidgets('a numeric edit marks the line Item Edited without a name change',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VoucherDetailSheet(payload: _payload)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Item Edited'), findsNothing);

    // Edit WIDGET A's qty. The stock item name never changes, so the original
    // name-diff logic can't see this — only the explicit touch tracking can.
    await tester.enterText(find.widgetWithText(TextFormField, '2'), '3');
    await tester.pump();

    expect(find.text('Item Edited'), findsOneWidget,
        reason: 'an explicit qty edit must mark the line as dealt with');
  });

  testWidgets('re-picking the SAME item from the dropdown marks the line',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Without a party_name the picker's _party resolves to null, so it skips
    // the party-specific Supabase fetch and reads straight from this primed
    // catalog — no network anywhere in the flow.
    StockItemsCache.instance.items = [
      const StockItem(name: 'WIDGET A', groupName: 'TOOLS', rate: 999, unit: 'NOS'),
    ];
    addTearDown(StockItemsCache.instance.clear);
    final partyless = Map<String, dynamic>.from(_payload)..remove('party_name');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VoucherDetailSheet(payload: partyless)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Item Edited'), findsNothing);

    // Open the picker from row 1's name, then pick the identical item. The name
    // ends up unchanged — the sheet must still register the line as dealt with.
    await tester.tap(find.text('WIDGET A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WIDGET A').last);
    await tester.pumpAndSettle();

    expect(find.text('Item Edited'), findsOneWidget,
        reason: 'a deliberate same-item re-pick must mark the line as dealt with');
  });

  // The sales-quote site swaps the green action for an inert "Send To Email".
  // Nothing else about the sheet moves, so pin both sides of the branch.
  group('the green action follows the site', () {
    Future<void> pumpSheet(WidgetTester tester, {SiteConfig? site}) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: VoucherDetailSheet(payload: _payload, site: site)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('default sites push to Tally', (tester) async {
      await pumpSheet(tester);
      expect(find.text('Push To Tally'), findsOneWidget);
      expect(find.text('Send To Email'), findsNothing);
    });

    testWidgets('sales-quote sends to email instead', (tester) async {
      await pumpSheet(tester, site: SiteConfig.salesQuote);
      expect(find.text('Send To Email'), findsOneWidget);
      expect(find.text('Push To Tally'), findsNothing);
    });

    // Tapping it closes the sheet and says so — no push, no status change. Opened
    // as a real modal route, the way the queue opens it, so the pop is the pop.
    testWidgets('Send To Email closes the sheet and confirms', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => const VoucherDetailSheet(
                  payload: _payload,
                  site: SiteConfig.salesQuote,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Send To Email'), findsOneWidget);

      await tester.tap(find.text('Send To Email'));
      await tester.pumpAndSettle();

      expect(find.text('Send To Email'), findsNothing, reason: 'sheet closed');
      expect(find.text('Sent to email'), findsOneWidget);
    });
  });
}
