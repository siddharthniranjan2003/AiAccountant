import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/site_config.dart';
import 'package:aiaccountant/shared/app_bottom_nav.dart';

// AppBottomNav is a plain StatelessWidget over currentIndex + onSelected, so it
// pumps without Firebase or Supabase — unlike AccountantApp, which can't be
// pumped at all (AuthGate reads FirebaseAuth.instance).
//
// `site` is the test seam: SiteConfig.current comes from a compile-time define,
// so a single test process can only vary it by injection.
Widget _host({
  required int currentIndex,
  required ValueChanged<int> onSelected,
  SiteConfig site = SiteConfig.full,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AppBottomNav(
        currentIndex: currentIndex,
        onSelected: onSelected,
        site: site,
      ),
    ),
  );
}

List<String?> _labels(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(AppBottomNav),
      matching: find.byType(Text),
    ))
    .map((t) => t.data)
    .toList();

void main() {
  // Tests run on the VM, so kIsWeb is false and the Camera entry (Android-only,
  // hidden on web) is drawn.
  group('AppBottomNav lays out the site it is given', () {
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
  });

  group('AppBottomNav', () {
    // An index is a position in THIS site's destination list, nothing more.
    // Profile is 4 on full and 2 on ops, and both are correct.
    testWidgets('reports the tapped position within the site', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(_host(currentIndex: 1, onSelected: taps.add));

      await tester.tap(find.text('Camera'));
      await tester.tap(find.text('History'));
      await tester.tap(find.text('Report'));
      await tester.tap(find.text('Profile'));
      expect(taps, [0, 2, 3, 4]);

      taps.clear();
      await tester.pumpWidget(
          _host(currentIndex: 0, onSelected: taps.add, site: SiteConfig.ops));

      await tester.tap(find.text('History'));
      await tester.tap(find.text('Profile'));
      expect(taps, [1, 2]);
    });

    // The point of an earlier change: Camera used to be a raised, accent-filled
    // 52px circle offset -18 out of the bar. Every tab is now the same 40px
    // circle, sitting in the row like its neighbours.
    testWidgets('draws no raised camera bump', (tester) async {
      await tester.pumpWidget(_host(currentIndex: 1, onSelected: (_) {}));

      final circles = tester
          .widgetList<AnimatedContainer>(find.descendant(
            of: find.byType(AppBottomNav),
            matching: find.byType(AnimatedContainer),
          ))
          .toList();
      expect(circles, hasLength(SiteConfig.full.destinations.length));

      final sizes = tester
          .widgetList<Icon>(find.descendant(
            of: find.byType(AppBottomNav),
            matching: find.byType(Icon),
          ))
          .map((i) => i.size)
          .toSet();
      expect(sizes, {20.0}, reason: 'every tab icon is the same size');

      expect(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.byType(Transform),
        ),
        findsNothing,
        reason: 'the Transform.translate that lifted the camera is gone',
      );
    });

    testWidgets('marks only the selected tab', (tester) async {
      await tester.pumpWidget(_host(currentIndex: 1, onSelected: (_) {}));

      // The selected tab is the one carrying the underline (a Positioned bar).
      expect(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.byType(Positioned),
        ),
        findsOneWidget,
      );
    });
  });
}
