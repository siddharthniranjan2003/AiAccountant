import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/constants.dart';
import 'package:aiaccountant/core/models.dart';
import 'package:aiaccountant/core/site_config.dart';

// The three websites are these four lists. Everything else — both nav bars, the
// shell's IndexedStack, the landing screen — is derived from them, so pinning
// them here is what stops a site silently gaining or losing a screen.
// Every site there is. A new one belongs here, so the "opens on a screen it
// ships" and "distinct title" checks cover it without being edited again.
const _allSites = [
  SiteConfig.full,
  SiteConfig.ops,
  SiteConfig.rate,
  SiteConfig.salesQuote,
];

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

    test('sales-quote is Queue, History, Rate, Report, Profile', () {
      expect(SiteConfig.salesQuote.destinations, [
        AppDestination.queue,
        AppDestination.history,
        AppDestination.rate,
        AppDestination.report,
        AppDestination.profile,
      ]);
      expect(SiteConfig.salesQuote.home, AppDestination.queue);
    });

    test('every site opens on a screen it actually ships', () {
      for (final site in _allSites) {
        expect(site.destinations, contains(site.home), reason: site.title);
      }
    });

    test('every site has a distinct browser title', () {
      final titles = _allSites.map((s) => s.title).toSet();
      expect(titles, hasLength(_allSites.length));
    });
  });

  // The three behaviour fields. They exist for sales-quote; the point of their
  // defaults is that adding them changed nothing for the sites that came first,
  // so pin both halves.
  group('site behaviour', () {
    test('sales-quote is sale-only, image-less, and mails instead of pushing', () {
      expect(SiteConfig.salesQuote.onlyType, TransactionType.sale);
      expect(SiteConfig.salesQuote.showsInvoiceImage, isFalse);
      expect(SiteConfig.salesQuote.voucherAction, VoucherAction.sendToEmail);
      expect(SiteConfig.salesQuote.createsStockItems, isFalse);
    });

    test('every other site keeps both types, the image, and Push To Tally', () {
      for (final site in [SiteConfig.full, SiteConfig.ops, SiteConfig.rate]) {
        expect(site.onlyType, isNull, reason: site.title);
        expect(site.showsInvoiceImage, isTrue, reason: site.title);
        expect(site.voucherAction, VoucherAction.pushToTally, reason: site.title);
        expect(site.createsStockItems, isTrue, reason: site.title);
      }
    });
  });

  group('SITE flag', () {
    test('selects the matching site', () {
      expect(SiteConfig.forFlag('ops'), same(SiteConfig.ops));
      expect(SiteConfig.forFlag('rate'), same(SiteConfig.rate));
      expect(SiteConfig.forFlag('sales-quote'), same(SiteConfig.salesQuote));
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
