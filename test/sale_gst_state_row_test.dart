import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/features/queue/voucher_detail_sheet.dart';

// A pending sale row auto-opens in edit mode and, with no __row_id, never writes
// to Supabase. The party-state lookup does reach for Supabase.instance, but it is
// wrapped in try/catch and resolves to '' (unknown) here — which is exactly the
// "no state recorded" case the picker exists to fix.
//
// Taxable value is 1000.00, so the arithmetic is easy to read:
//   intra-state -> CGST 90.00 + SGST 90.00   (9% each)
//   inter-state -> IGST 180.00               (18%)
Map<String, dynamic> _salePayload() => {
      '__status': 'pending',
      'party_name': 'ACME TRADERS',
      'voucher_type': 'GST SALE',
      'voucher_number': 'SALE-1',
      'date': '2026-07-01',
      'inventory_ledger_name': 'GST SALE',
      'items': [
        {'stock_item_name': 'WIDGET A', 'quantity': 10, 'rate': 100, 'amount': 1000},
      ],
      'ledger_entries': <Map<String, dynamic>>[
        {'ledger_name': 'ACME TRADERS', 'amount': 1180.0, 'is_deemed_positive': true},
        {'ledger_name': 'GST SALE', 'amount': 1000.0, 'is_deemed_positive': false},
        {'ledger_name': 'CGST', 'amount': 90.0, 'is_deemed_positive': false},
        {'ledger_name': 'SGST', 'amount': 90.0, 'is_deemed_positive': false},
      ],
    };

Future<void> _mount(WidgetTester tester, Map<String, dynamic> payload) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: VoucherDetailSheet(payload: payload)),
  ));
  await tester.pumpAndSettle();
}

/// Picks [state] from the sheet's State row.
Future<void> _pickState(WidgetTester tester, String state) async {
  await tester.tap(find.text('Select state'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, state);
  await tester.pumpAndSettle();
  await tester.tap(find.text(state).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a sale sheet shows the State row above the tax rows',
      (tester) async {
    await _mount(tester, _salePayload());

    expect(find.text('State'), findsOneWidget);
    // No state on the ledger -> prompt, and the intra-state split stands.
    expect(find.text('Select state'), findsOneWidget);
    expect(find.text('Add: CGST'), findsOneWidget);
    expect(find.text('Add: SGST'), findsOneWidget);
    expect(find.text('Add: IGST'), findsNothing);
  });

  testWidgets('picking an out-of-state value swaps CGST+SGST for a single IGST',
      (tester) async {
    await _mount(tester, _salePayload());
    await _pickState(tester, 'Delhi');

    expect(find.text('Add: IGST'), findsOneWidget,
        reason: 'an out-of-state party must book inter-state GST');
    expect(find.text('Add: CGST'), findsNothing,
        reason: 'the intra-state rows must be REMOVED, not just rescaled');
    expect(find.text('Add: SGST'), findsNothing);
    expect(find.text('Delhi'), findsWidgets);
  });

  testWidgets('the swap survives Save — ledger_entries are rebuilt, not remapped',
      (tester) async {
    // The tests above assert on _editableLedgers via the rendered rows. This one
    // covers the separate write path: tapping Save runs _writeChargesBack, which
    // used to map 1:1 over the ORIGINAL ledger_entries. That mapping cannot add
    // an IGST row that was never there, nor drop the CGST/SGST rows that were —
    // so without the rebuild the sheet would snap back to CGST+SGST here.
    await _mount(tester, _salePayload());
    await _pickState(tester, 'Delhi');
    expect(find.text('Add: IGST'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Now out of edit mode, the rows render from the saved payload.
    expect(find.text('Edit'), findsOneWidget, reason: 'save should exit edit mode');
    expect(find.text('Add: IGST'), findsOneWidget,
        reason: 'the saved payload must carry the IGST row that was added');
    expect(find.text('Add: CGST'), findsNothing,
        reason: 'the saved payload must not keep the orphaned intra-state rows');
    expect(find.text('Add: SGST'), findsNothing);
  });

  testWidgets('Revert undoes a state pick — tax rows and the State row go back',
      (tester) async {
    // Nothing is written to Supabase on pick (Save is the only commit point), so a
    // Revert before Save must leave no trace: the tax rows return to the parser's
    // split and the picked state is dropped.
    await _mount(tester, _salePayload());
    await _pickState(tester, 'Delhi');
    expect(find.text('Add: IGST'), findsOneWidget);
    expect(find.text('Delhi'), findsWidgets);

    await tester.tap(find.text('Revert'));
    await tester.pumpAndSettle();

    expect(find.text('Add: CGST'), findsOneWidget,
        reason: 'revert must restore the original intra-state split');
    expect(find.text('Add: SGST'), findsOneWidget);
    expect(find.text('Add: IGST'), findsNothing);
    expect(find.text('Delhi'), findsNothing,
        reason: 'the picked state must be dropped, back to the loaded value');
  });

  testWidgets('picking the home state splits IGST back into CGST+SGST',
      (tester) async {
    // The reverse direction — this is the case that breaks if _writeChargesBack
    // maps 1:1 over the existing ledger_entries instead of rebuilding them.
    final igstPayload = _salePayload()
      ..['ledger_entries'] = <Map<String, dynamic>>[
        {'ledger_name': 'ACME TRADERS', 'amount': 1180.0, 'is_deemed_positive': true},
        {'ledger_name': 'GST SALE', 'amount': 1000.0, 'is_deemed_positive': false},
        {'ledger_name': 'IGST', 'amount': 180.0, 'is_deemed_positive': false},
      ];
    await _mount(tester, igstPayload);
    expect(find.text('Add: IGST'), findsOneWidget);

    await _pickState(tester, 'Haryana');

    expect(find.text('Add: CGST'), findsOneWidget,
        reason: 'the home state must ADD two rows that were not there before');
    expect(find.text('Add: SGST'), findsOneWidget);
    expect(find.text('Add: IGST'), findsNothing);
  });
}
