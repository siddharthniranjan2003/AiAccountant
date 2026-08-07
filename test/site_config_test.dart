import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/constants.dart';
import 'package:aiaccountant/core/site_config.dart';

// The two websites are these three lists. Everything else — both nav bars, the
// shell's IndexedStack, the landing screen — is derived from them, so pinning
// them here is what stops a site silently gaining or losing a screen.
void main() {
  group('site destinations', () {
    test('full is the whole app', () {
      expect(SiteConfig.full.destinations, [
        AppDestination.camera,
        AppDestination.queue,
        AppDestination.history,
        AppDestination.report,
        AppDestination.profile,
      ]);
      expect(SiteConfig.full.home, AppDestination.queue);
    });

    test('ops is Queue, History, Profile — no Camera, no Report, no Rate', () {
      expect(SiteConfig.ops.destinations, [
        AppDestination.queue,
        AppDestination.history,
        AppDestination.profile,
      ]);
      expect(SiteConfig.ops.home, AppDestination.queue);
    });

    test('rate is Rate, Report, Profile — no Queue, no History', () {
      expect(SiteConfig.rate.destinations, [
        AppDestination.rate,
        AppDestination.report,
        AppDestination.profile,
      ]);
      expect(SiteConfig.rate.home, AppDestination.rate);
    });

    test('every site opens on a screen it actually ships', () {
      for (final site in [SiteConfig.full, SiteConfig.ops, SiteConfig.rate]) {
        expect(site.destinations, contains(site.home), reason: site.title);
      }
    });

    test('every site has a distinct browser title', () {
      final titles = [SiteConfig.full, SiteConfig.ops, SiteConfig.rate]
          .map((s) => s.title)
          .toSet();
      expect(titles, hasLength(3));
    });
  });

  group('SITE flag', () {
    test('selects the matching site', () {
      expect(SiteConfig.forFlag('ops'), same(SiteConfig.ops));
      expect(SiteConfig.forFlag('rate'), same(SiteConfig.rate));
    });

    // A typo in a build script should ship the complete app rather than a
    // blank one, so unknown values fall back instead of throwing.
    test('falls back to full when absent or unrecognised', () {
      expect(SiteConfig.forFlag(''), same(SiteConfig.full));
      expect(SiteConfig.forFlag('full'), same(SiteConfig.full));
      expect(SiteConfig.forFlag('Ops'), same(SiteConfig.full));
      expect(SiteConfig.forFlag('nonsense'), same(SiteConfig.full));
    });

    test('a bare build is the full app', () {
      expect(SiteConfig.current, same(SiteConfig.full));
    });
  });

  // A destination with no nav entry would throw on the null assertion when a
  // bar tried to draw it.
  test('every destination can be drawn in the nav', () {
    for (final destination in AppDestination.values) {
      expect(navItemFor[destination], isNotNull, reason: '$destination');
      expect(navItemFor[destination]!.label, isNotEmpty);
    }
  });
}
