import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/site_config.dart';
import 'package:aiaccountant/shared/app_side_nav.dart';

// The desktop rail used to hardcode positions against the nav list (_item(3) =
// Report, _item(4) = Profile) and to carry a Stock Info launcher that was not a
// destination at all, so restoring a hidden screen silently sent every entry
// below it somewhere else. It now iterates the site's list and nothing else —
// these tests are what keep it that way.
Widget _host({
  required int currentIndex,
  required ValueChanged<int> onSelected,
  SiteConfig site = SiteConfig.full,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AppSideNav(
        currentIndex: currentIndex,
        onSelected: onSelected,
        site: site,
      ),
    ),
  );
}

List<String?> _labels(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(AppSideNav),
      matching: find.byType(Text),
    ))
    .map((t) => t.data)
    .toList();

void main() {
  // Tests run on the VM (kIsWeb false), so Camera is drawn on `full`.
  group('AppSideNav renders the site in nav order', () {
    testWidgets('full — Camera, Queue, History, Report, Profile',
        (tester) async {
      await tester.pumpWidget(_host(currentIndex: 1, onSelected: (_) {}));
      expect(_labels(tester),
          ['Camera', 'Queue', 'History', 'Report', 'Profile']);
    });

    testWidgets('ops — Queue, History, Profile', (tester) async {
      await tester.pumpWidget(
          _host(currentIndex: 0, onSelected: (_) {}, site: SiteConfig.ops));
      expect(_labels(tester), ['Queue', 'History', 'Profile']);
    });

    testWidgets('rate — Rate, Report, Profile', (tester) async {
      await tester.pumpWidget(
          _host(currentIndex: 0, onSelected: (_) {}, site: SiteConfig.rate));
      expect(_labels(tester), ['Rate', 'Report', 'Profile']);
    });

    testWidgets('sales-quote — Queue, History, Rate, Report, Profile',
        (tester) async {
      await tester.pumpWidget(_host(
          currentIndex: 0, onSelected: (_) {}, site: SiteConfig.salesQuote));
      expect(_labels(tester),
          ['Queue', 'History', 'Rate', 'Report', 'Profile']);
    });

    // Rate reaches the rail only as a destination of the site that has one.
    // Elsewhere stock info is reached from the ⓘ inside a voucher's items —
    // there is no standalone launcher in the rail any more.
    testWidgets('no Rate launcher on sites without a Rate screen',
        (tester) async {
      await tester.pumpWidget(_host(currentIndex: 1, onSelected: (_) {}));
      expect(find.text('Rate'), findsNothing);

      await tester.pumpWidget(
          _host(currentIndex: 0, onSelected: (_) {}, site: SiteConfig.ops));
      expect(find.text('Rate'), findsNothing);
    });
  });

  group('AppSideNav selection', () {
    testWidgets('reports the position within the site', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
          _host(currentIndex: 0, onSelected: taps.add, site: SiteConfig.ops));

      await tester.tap(find.text('Queue'));
      await tester.tap(find.text('History'));
      await tester.tap(find.text('Profile'));
      expect(taps, [0, 1, 2]);
    });

    testWidgets('marks only the selected entry', (tester) async {
      await tester.pumpWidget(
          _host(currentIndex: 1, onSelected: (_) {}, site: SiteConfig.ops));

      // Selection is a vertical bar on the left edge (a Positioned).
      expect(
        find.descendant(
          of: find.byType(AppSideNav),
          matching: find.byType(Positioned),
        ),
        findsOneWidget,
      );
    });
  });
}
