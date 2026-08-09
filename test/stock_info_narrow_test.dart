import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/features/stock/stock_info_screen.dart';
import 'package:aiaccountant/services/stock_info_route.dart';

/// Phone-width coverage for the Rate window. `stock_info_route_test.dart` pumps
/// it at 1400×1000, which is exactly the width where nothing overflows.
///
/// A RenderFlex that runs out of room reports through `FlutterError.reportError`,
/// which the test binding captures — so `tester.takeException()` is the assertion
/// that matters here, not any particular finder.
///
/// Scope, stated honestly: these cases pass against the pre-responsive screen
/// too. The overflow that motivated this work is in the history table, and the
/// table is unreachable from a widget test — the screen is pumped with an empty
/// item so `initState` returns before touching Supabase, and a non-empty route's
/// loads swallow the un-initialized-Supabase throw into the panels' error
/// fields, so `_TxnRow` never renders. There is no seam to inject rows through
/// without widening the screen's public API.
///
/// So this file guards the parts that *are* reachable at phone width — the
/// search bar, the name header, the empty state, the party filter row — against
/// future regressions. The reflowed table is verified by hand in Chrome at 390px.
void main() {
  group('StockInfoScreen at phone width', () {
    Future<StreamController<StockInfoRoute>> pump(WidgetTester tester) async {
      final routes = StreamController<StockInfoRoute>.broadcast();
      addTearDown(routes.close);
      tester.view.physicalSize = const Size(390, 844); // iPhone 12 Pro
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        // Mirrors main.dart's MediaQuery builder. Tests bypass that builder, and
        // without the 1.4 scaler the text measures 40% narrower than it does on
        // the live web build — i.e. the overflow this file exists to catch would
        // not reproduce.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: StockInfoScreen(itemName: '', routeChanges: routes.stream),
      ));
      await tester.pumpAndSettle();
      return routes;
    }

    testWidgets('the blank search state fits', (tester) async {
      await pump(tester);

      expect(
        find.textContaining('Search a stock item above'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    // The customer chip and the "add customer" button share one line above the
    // Sale table; on a phone that line has ~300px to work with.
    testWidgets('a long party name does not overflow the filter row',
        (tester) async {
      final routes = await pump(tester);

      routes.add(const StockInfoRoute(
        item: 'HSS ENDMILL 37 ADDISON',
        party: 'MOHIT SALES AGENCIES AND DISTRIBUTORS PRIVATE LIMITED',
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The name header is now capped at two lines; this pins that a long name
    // stays inside the viewport rather than growing the header unbounded.
    testWidgets('a long item name stays bounded', (tester) async {
      final routes = await pump(tester);

      routes.add(const StockInfoRoute(
        item: 'CARBIDE TIPPED PARALLEL SHANK TWIST DRILL 12.40MM '
            'LONG SERIES ADDISON GRADE K20',
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
