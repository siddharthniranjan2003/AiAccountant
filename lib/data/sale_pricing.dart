import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_reporter.dart';

/// Sale pricing for one stock item, resolved from voucher history.
///
/// Rate and discount are **independent lookups** and routinely come from
/// different vouchers — that is the point of the rule, not a bug:
///
///   rate     = latest GST SALE of the item to ANYONE   (party irrelevant)
///   discount = latest GST SALE of the item to THIS party; none -> 0%
///
/// So an item can carry another customer's current market rate alongside this
/// customer's own negotiated discount. `rateSource` / `discountSource` record
/// which happened, and are written to `push_queue.source_payload`.
class SalePricing {
  const SalePricing({
    required this.rate,
    required this.discountPct,
    required this.rateSource,
    required this.discountSource,
  });

  /// Gross rate, before the discount. Zero when the item has never been sold.
  final double rate;

  /// Percent off the gross. Zero when this party has no history for the item.
  final double discountPct;

  /// 'same_party' | 'different_party' | 'none'
  final String rateSource;

  /// 'same_party' | 'none'
  final String discountSource;

  /// What a caller uses for an item the lookup returned nothing for.
  static const none = SalePricing(
    rate: 0.0,
    discountPct: 0.0,
    rateSource: 'none',
    discountSource: 'none',
  );
}

/// Resolves rate + discount for [itemNames], scoped to [party] for the discount.
///
/// Returns `{stockItemName: SalePricing}`. A name **absent from the result** has
/// never been sold to anyone — callers treat that as [SalePricing.none] (rate 0).
///
/// This is the app-side twin of `build_sale_rate_map_global` in the parsing
/// service (`TallyBridge/parsing/server/handler.py`). Both call the same two
/// Postgres functions, so the numbers cannot drift the way they did when each
/// side carried its own copy of the rule.
///
/// Two batch RPCs regardless of list size, so repricing a whole picker list
/// costs the same two round-trips as repricing one item.
///
/// Never throws. A failure degrades to `{}` — every line then prices at 0, which
/// is visible and safe, rather than a plausible wrong number. This is also
/// load-bearing for the widget tests, which run with Supabase uninitialised.
Future<Map<String, SalePricing>> resolveSalePricing({
  required String? party,
  required List<String> itemNames,
}) async {
  final names = itemNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet().toList();
  if (names.isEmpty) return {};

  try {
    final client = Supabase.instance.client;

    // Rate: latest GST SALE to anyone. party_name comes back only so we can
    // label the source; it is never shown as the price's owner.
    final rateRes = await client.rpc(
      'get_latest_sale_rates_for_items',
      params: {'p_item_names': names},
    );
    final rateRows = (rateRes as List).cast<Map<String, dynamic>>();

    // Discount: latest GST SALE to THIS party. With no party there is nobody to
    // scope to, so every line is a genuine 0% rather than an unknown.
    var discountRows = <Map<String, dynamic>>[];
    if (party != null && party.trim().isNotEmpty) {
      final discRes = await client.rpc(
        'get_latest_party_discounts_for_items',
        params: {'p_party_name': party, 'p_item_names': names},
      );
      discountRows = (discRes as List).cast<Map<String, dynamic>>();
    }

    return mergeSalePricing(
      party: party,
      rateRows: rateRows,
      discountRows: discountRows,
    );
  } catch (e, st) {
    reportHandledError('supabase.picker.sale_pricing', e, stackTrace: st);
    return {};
  }
}

/// The merge half of [resolveSalePricing] — the part worth pinning down.
///
/// Split out and left package-visible so the tests can reach it: this repo has
/// no mocking framework, so there is no way to intercept the Supabase client,
/// and testing the rule end-to-end would mean testing the network.
/// [resolveSalePricing] fetches and delegates here, so there is exactly one copy
/// of the rule.
Map<String, SalePricing> mergeSalePricing({
  required String? party,
  required List<Map<String, dynamic>> rateRows,
  required List<Map<String, dynamic>> discountRows,
}) {
  // Presence, not value. A row carrying 0.0 means "this party's most recent sale
  // of the item genuinely carried no discount" and must read same_party; only an
  // ABSENT key means "never sold to them" -> none. Collapsing the two would
  // erase exactly the distinction this rule exists to make.
  final discounts = <String, double>{};
  for (final row in discountRows) {
    final name = (row['stock_item_name'] as String? ?? '').trim();
    if (name.isEmpty) continue;
    discounts[name] = (row['discount_pct'] as num?)?.toDouble() ?? 0.0;
  }

  final partyKey = (party ?? '').trim().toLowerCase();
  final out = <String, SalePricing>{};
  for (final row in rateRows) {
    final name = (row['stock_item_name'] as String? ?? '').trim();
    if (name.isEmpty) continue;
    final winner = (row['party_name'] as String? ?? '').trim().toLowerCase();
    out[name] = SalePricing(
      rate: (row['rate'] as num?)?.toDouble() ?? 0.0,
      discountPct: discounts[name] ?? 0.0,
      rateSource: (partyKey.isNotEmpty && winner == partyKey) ? 'same_party' : 'different_party',
      discountSource: discounts.containsKey(name) ? 'same_party' : 'none',
    );
  }
  return out;
}
