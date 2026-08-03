import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/constants.dart';
import 'package:aiaccountant/shared/app_bottom_nav.dart';

// AppBottomNav is a plain StatelessWidget over currentIndex + onSelected, so it
// pumps without Firebase or Supabase — unlike AccountantApp, which can't be
// pumped at all (AuthGate reads FirebaseAuth.instance).
Widget _host({required int currentIndex, required ValueChanged<int> onSelected}) {
  return MaterialApp(
    home: Scaffold(
      body: AppBottomNav(currentIndex: currentIndex, onSelected: onSelected),
    ),
  );
}

void main() {
  // Four files key off these positions: app_shell routes kCameraNavIndex to the
  // scanner and opens on kQueueNavIndex, and app_side_nav hardcodes rail entries
  // against the same list. A silent desync here sends every tab to the wrong
  // screen rather than throwing, so pin the two that carry meaning.
  group('nav index constants', () {
    test('point at the entries the rest of the app assumes', () {
      expect(bottomNavItems[kCameraNavIndex].label, 'Camera');
      expect(bottomNavItems[kQueueNavIndex].label, 'Queue');
    });
  });

  group('AppBottomNav', () {
    testWidgets('lays the tabs out Camera, Queue, History, Profile',
        (tester) async {
      await tester.pumpWidget(_host(currentIndex: kQueueNavIndex, onSelected: (_) {}));

      final labels = tester
          .widgetList<Text>(find.descendant(
            of: find.byType(AppBottomNav),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .toList();
      expect(labels, ['Camera', 'Queue', 'History', 'Profile']);
    });

    testWidgets('reports the tapped index', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(_host(currentIndex: kQueueNavIndex, onSelected: taps.add));

      await tester.tap(find.text('Camera'));
      await tester.tap(find.text('History'));
      await tester.tap(find.text('Profile'));
      expect(taps, [kCameraNavIndex, 2, 3]);
    });

    // The point of the change: Camera used to be a raised, accent-filled 52px
    // circle offset -18 out of the bar. Every tab is now the same 40px circle,
    // sitting in the row like its neighbours.
    testWidgets('draws no raised camera bump', (tester) async {
      await tester.pumpWidget(_host(currentIndex: kQueueNavIndex, onSelected: (_) {}));

      final circles = tester
          .widgetList<AnimatedContainer>(find.descendant(
            of: find.byType(AppBottomNav),
            matching: find.byType(AnimatedContainer),
          ))
          .toList();
      expect(circles, hasLength(bottomNavItems.length));

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
      await tester.pumpWidget(_host(currentIndex: kQueueNavIndex, onSelected: (_) {}));

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
