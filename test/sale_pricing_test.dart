import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/data/sale_pricing.dart';

// The sale pricing rule, as implemented by mergeSalePricing and by
// build_sale_rate_map_global in the parsing service. Both consume the same two
// Postgres functions; these tests pin the merge half, which is the part that
// used to drift between the app and the backend.
//
//   rate     = latest GST SALE of the item to ANYONE   (party irrelevant)
//   discount = latest GST SALE of the item to THIS party; none -> 0%
//
// Ordering/tie-breaks live in SQL and are not re-tested here — the rows below
// are what the RPCs already picked.

const _party = 'A.V. UNIPACK PRIVATE LIMITED';

Map<String, dynamic> _rate(String name, num rate, String party) =>
    {'stock_item_name': name, 'rate': rate, 'party_name': party};

Map<String, dynamic> _disc(String name, num pct) =>
    {'stock_item_name': name, 'discount_pct': pct};

void main() {
  test('rate from another party, discount from this one — the headline case', () {
    // Real shape from the client invoice: the rate is the newest sale to anyone,
    // the discount is this customer's own standing term, and they come from two
    // different vouchers. That combination is the whole point of the rule.
    final out = mergeSalePricing(
      party: _party,
      rateRows: [_rate('HSS TAP 12 X 1.75 SEC TOTEM', 1042, 'R.B. TRADERS')],
      discountRows: [_disc('HSS TAP 12 X 1.75 SEC TOTEM', 45.5)],
    );
    final p = out['HSS TAP 12 X 1.75 SEC TOTEM']!;
    expect(p.rate, 1042);
    expect(p.discountPct, 45.5);
    expect(p.rateSource, 'different_party');
    expect(p.discountSource, 'same_party');
  });

  test('never sold to this party -> 0% and discount_source none', () {
    final out = mergeSalePricing(
      party: _party,
      rateRows: [_rate('SOLID CARBIDE DRILL 2.8 TOTEM', 1850, 'ESKO CASTING')],
      discountRows: const [],
    );
    final p = out['SOLID CARBIDE DRILL 2.8 TOTEM']!;
    expect(p.rate, 1850);
    expect(p.discountPct, 0.0);
    expect(p.discountSource, 'none');
  });

  // The distinction the whole change exists to make. Both of these put 0.0 in
  // discountPct; only discountSource separates "their last sale genuinely had no
  // discount" from "we have never sold it to them". A merge that keyed off the
  // VALUE being falsy instead of the KEY being present would collapse them.
  test('a real 0% is same_party, not none', () {
    final out = mergeSalePricing(
      party: _party,
      rateRows: [_rate('WIDGET', 100, 'SOMEONE ELSE')],
      discountRows: [_disc('WIDGET', 0)],
    );
    expect(out['WIDGET']!.discountPct, 0.0);
    expect(out['WIDGET']!.discountSource, 'same_party');
  });

  test('an absent discount row is none, with the same 0.0 value', () {
    final out = mergeSalePricing(
      party: _party,
      rateRows: [_rate('WIDGET', 100, 'SOMEONE ELSE')],
      discountRows: const [],
    );
    expect(out['WIDGET']!.discountPct, 0.0);
    expect(out['WIDGET']!.discountSource, 'none');
  });

  test('the latest sale happening to be to this party reads same_party', () {
    final out = mergeSalePricing(
      party: _party,
      rateRows: [_rate('WIDGET', 834, _party)],
      discountRows: [_disc('WIDGET', 55)],
    );
    expect(out['WIDGET']!.rateSource, 'same_party');
  });

  test('party match is case- and whitespace-insensitive', () {
    final out = mergeSalePricing(
      party: '  a.v. unipack private limited ',
      rateRows: [_rate('WIDGET', 834, _party)],
      discountRows: const [],
    );
    expect(out['WIDGET']!.rateSource, 'same_party');
  });

  test('an item with no rate row is absent entirely, not zero-valued', () {
    // Callers substitute SalePricing.none, which reads rate_source 'none' —
    // distinct from a different_party rate that happens to be 0.
    final out = mergeSalePricing(
      party: _party,
      rateRows: [_rate('SOLD', 10, 'X')],
      discountRows: const [],
    );
    expect(out.containsKey('NEVER SOLD'), isFalse);
    expect(SalePricing.none.rateSource, 'none');
    expect(SalePricing.none.discountSource, 'none');
  });

  test('a rate of 0 still resolves — no hygiene filter, by design', () {
    final out = mergeSalePricing(
      party: _party,
      rateRows: [_rate('WIDGET', 0, 'X')],
      discountRows: const [],
    );
    expect(out['WIDGET']!.rate, 0.0);
    expect(out['WIDGET']!.rateSource, 'different_party');
  });

  test('no party means no discount lookup ran — everything is none', () {
    final out = mergeSalePricing(
      party: null,
      rateRows: [_rate('WIDGET', 500, 'X')],
      discountRows: const [],
    );
    expect(out['WIDGET']!.rate, 500);
    expect(out['WIDGET']!.discountSource, 'none');
    // With no party to compare against, the winner can't be "same party".
    expect(out['WIDGET']!.rateSource, 'different_party');
  });

  test('blank and null field values degrade instead of throwing', () {
    final out = mergeSalePricing(
      party: _party,
      rateRows: [
        {'stock_item_name': 'WIDGET', 'rate': null, 'party_name': null},
        {'stock_item_name': '  ', 'rate': 5, 'party_name': 'X'},
      ],
      discountRows: [
        {'stock_item_name': 'WIDGET', 'discount_pct': null},
      ],
    );
    expect(out.length, 1); // the blank-named row is dropped
    expect(out['WIDGET']!.rate, 0.0);
    expect(out['WIDGET']!.discountPct, 0.0);
    expect(out['WIDGET']!.discountSource, 'same_party'); // key present
  });

  // The load-bearing failure contract. resolveSalePricing must never throw:
  // with Supabase uninitialised (as in every widget test in this repo) it has to
  // degrade to {} so callers fall back to SalePricing.none. If this regresses,
  // the picker throws instead of pricing at 0 and the widget tests fail with it.
  test('resolveSalePricing degrades to {} when Supabase is unavailable', () async {
    final out = await resolveSalePricing(party: _party, itemNames: ['WIDGET']);
    expect(out, isEmpty);
  });

  test('an empty name list short-circuits without touching the network', () async {
    expect(await resolveSalePricing(party: _party, itemNames: const []), isEmpty);
    expect(await resolveSalePricing(party: _party, itemNames: ['', '   ']), isEmpty);
  });

  test('multiple items resolve independently in one batch', () {
    final out = mergeSalePricing(
      party: _party,
      rateRows: [
        _rate('A', 100, _party),
        _rate('B', 200, 'OTHER'),
        _rate('C', 300, 'OTHER'),
      ],
      discountRows: [_disc('A', 55), _disc('B', 0)],
    );
    expect(out['A']!.rateSource, 'same_party');
    expect(out['A']!.discountSource, 'same_party');
    expect(out['B']!.rateSource, 'different_party');
    expect(out['B']!.discountSource, 'same_party'); // real 0%
    expect(out['C']!.discountSource, 'none'); // no history
  });
}
