import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/features/stock/stock_info_screen.dart';
import 'package:aiaccountant/services/stock_info_route.dart';

void main() {
  // Both the cold-boot path (main.dart) and the retarget path
  // (StockInfoScreen's hashchange listener) read the fragment through this, so
  // a window that is reused shows the same thing a freshly opened one would.
  group('StockInfoRoute.parse', () {
    test('reads item and party', () {
      final r = StockInfoRoute.parse(
          '/stock-info?item=HSS%20ENDMILL%2037%20ADDISON&party=MOHIT%20SALES%20AGENCIES');
      expect(r?.item, 'HSS ENDMILL 37 ADDISON');
      expect(r?.party, 'MOHIT SALES AGENCIES');
    });

    test('a purchase row carries no party', () {
      final r = StockInfoRoute.parse('/stock-info?item=HSS%20DRILL%2012.4');
      expect(r?.item, 'HSS DRILL 12.4');
      expect(r?.party, isNull);
    });

    test('the Rate nav asks for the blank-search state', () {
      final r = StockInfoRoute.parse('/stock-info?item=');
      expect(r, isNotNull);
      expect(r?.item, isEmpty);
      expect(r?.party, isNull);
    });

    // '—' is the voucher sheet's unknown-party placeholder. The launcher filters
    // it outbound; parse refuses it inbound too, so a hand-edited URL can't
    // scope the Sale panel to a dash.
    test('normalizes the em-dash placeholder to no party', () {
      expect(StockInfoRoute.parse('/stock-info?item=X&party=%E2%80%94')?.party,
          isNull);
    });

    // A hash change that isn't a stock-info route must be ignored rather than
    // blanking the window.
    test('rejects anything that is not a stock-info route', () {
      expect(StockInfoRoute.parse(''), isNull);
      expect(StockInfoRoute.parse('/'), isNull);
      expect(StockInfoRoute.parse('/queue?item=X'), isNull);
    });
  });

  group('StockInfoScreen retargeting', () {
    // Pumped with an empty item, so initState returns before touching Supabase.
    // The load methods a non-empty route triggers swallow their own errors into
    // the panel error fields, so no Supabase setup is needed here either.
    Future<StreamController<StockInfoRoute>> pump(WidgetTester tester) async {
      final routes = StreamController<StockInfoRoute>.broadcast();
      addTearDown(routes.close);
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: StockInfoScreen(itemName: '', routeChanges: routes.stream),
      ));
      await tester.pumpAndSettle();
      return routes;
    }

    testWidgets('shows the item the retargeting click asked for',
        (tester) async {
      final routes = await pump(tester);

      routes.add(const StockInfoRoute(item: '16ER 14W', party: 'BALAJI TOOLS'));
      await tester.pumpAndSettle();

      expect(find.text('16ER 14W'), findsWidgets);
      expect(find.text('BALAJI TOOLS'), findsOneWidget,
          reason: 'the customer chip follows the incoming click');
    });

    // The decision that drove this feature: the incoming click always wins,
    // including overriding the chip to nothing.
    testWidgets('a party-less route clears the customer chip', (tester) async {
      final routes = await pump(tester);

      routes.add(const StockInfoRoute(item: '16ER 14W', party: 'BALAJI TOOLS'));
      await tester.pumpAndSettle();
      expect(find.text('BALAJI TOOLS'), findsOneWidget);

      // e.g. the ⓘ on a purchase row.
      routes.add(const StockInfoRoute(item: 'HSS TAP 12'));
      await tester.pumpAndSettle();
      expect(find.text('BALAJI TOOLS'), findsNothing);
      expect(find.text('HSS TAP 12'), findsWidgets);
    });

    // The Rate nav sends an empty item — the window goes back to blank search.
    testWidgets('an empty item clears the window', (tester) async {
      final routes = await pump(tester);

      routes.add(const StockInfoRoute(item: '16ER 14W', party: 'BALAJI TOOLS'));
      await tester.pumpAndSettle();
      expect(find.text('16ER 14W'), findsWidgets);

      routes.add(const StockInfoRoute(item: ''));
      await tester.pumpAndSettle();
      expect(find.text('16ER 14W'), findsNothing);
      expect(find.text('BALAJI TOOLS'), findsNothing);
    });
  });
}
