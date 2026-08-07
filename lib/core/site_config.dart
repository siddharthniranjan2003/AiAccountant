import 'package:flutter/foundation.dart';

/// A place the app can navigate to.
///
/// Named rather than numbered: every nav position used to be an index that
/// `constants.dart`, `app_shell.dart` and `app_side_nav.dart` each had to agree
/// on by hand, so hiding or restoring one screen silently shifted the ones below
/// it. Sites with different screen sets make that impossible to hold together,
/// hence names.
enum AppDestination { camera, queue, history, report, profile, rate }

/// Which screens this build navigates to, in nav order.
///
/// Chosen at BUILD time from the `SITE` dart-define. No define (Android,
/// `flutter run`, a bare `flutter build web`) means [full] — the whole app,
/// exactly as it behaves without any of this.
///
/// This gates navigation, not compilation: `app_shell`'s `_screenFor` switches
/// over every destination whatever the site, so all the screens are still in
/// the bundle. Not a security boundary.
@immutable
class SiteConfig {
  const SiteConfig({
    required this.title,
    required this.destinations,
    required this.home,
  });

  /// Browser tab title, via `MaterialApp.title`.
  final String title;

  /// Ordered — this IS the nav order, for both the bottom bar and the desktop
  /// rail. An "index" anywhere in the nav code is a position in this list.
  final List<AppDestination> destinations;

  /// Where the app opens. Always a member of [destinations].
  final AppDestination home;

  /// Everything. Android and local dev.
  static const SiteConfig full = SiteConfig(
    title: 'AI Accountant',
    destinations: [
      AppDestination.camera,
      AppDestination.queue,
      AppDestination.history,
      AppDestination.report,
      AppDestination.profile,
    ],
    home: AppDestination.queue,
  );

  /// Website 1 — the day-to-day voucher app. Web-only, so no Camera (the
  /// scanner is Android-only and the nav hides it on web anyway).
  static const SiteConfig ops = SiteConfig(
    title: 'AI Accountant — Queue',
    destinations: [
      AppDestination.queue,
      AppDestination.history,
      AppDestination.profile,
    ],
    home: AppDestination.queue,
  );

  /// Website 2 — rate lookup and reporting. Rate is a real screen here, unlike
  /// on [full] / [ops] where it stays the standalone popup window.
  static const SiteConfig rate = SiteConfig(
    title: 'AI Accountant — Rate',
    destinations: [
      AppDestination.rate,
      AppDestination.report,
      AppDestination.profile,
    ],
    home: AppDestination.rate,
  );

  static const String flag = String.fromEnvironment('SITE', defaultValue: 'full');

  static SiteConfig get current => forFlag(flag);

  /// Unknown values fall back to [full] rather than throwing: a typo in a build
  /// script should ship the complete app, not a blank one.
  static SiteConfig forFlag(String flag) => switch (flag) {
        'ops' => ops,
        'rate' => rate,
        _ => full,
      };
}
