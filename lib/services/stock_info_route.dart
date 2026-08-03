/// What a `#/stock-info?item=…&party=…` URL fragment asks the Stock Info window
/// to show.
///
/// The window is reused rather than reopened (see [StockInfoLauncher]), so the
/// same fragment shape has to be readable twice: once by `main.dart` when a
/// window boots cold, and again by `StockInfoScreen` when an already-open window
/// is retargeted. Parsing lives here so both agree by construction.
class StockInfoRoute {
  const StockInfoRoute({required this.item, this.party});

  /// The stock item to show. Empty means the Rate nav's blank-search state.
  final String item;

  /// Customer to scope the Sale panel to; null when the click carried none
  /// (a purchase row, or the Rate nav). An incoming route always overrides the
  /// window's current chip — including overriding it to nothing.
  final String? party;

  /// Reads a fragment such as `/stock-info?item=X&party=Y`. Returns null when
  /// [fragment] is not a stock-info route, so an unrelated hash change is
  /// ignored rather than blanking the window.
  static StockInfoRoute? parse(String fragment) {
    if (fragment.isEmpty) return null;
    final uri = Uri.tryParse(fragment);
    if (uri == null || uri.path != '/stock-info') return null;
    // '—' is the voucher sheet's unknown-party placeholder. The launcher already
    // filters it on the way out; treat it as "no party" here too so a
    // hand-edited URL can't scope the panel to a dash.
    final party = (uri.queryParameters['party'] ?? '').trim();
    return StockInfoRoute(
      item: (uri.queryParameters['item'] ?? '').trim(),
      party: (party.isEmpty || party == '—') ? null : party,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StockInfoRoute && other.item == item && other.party == party;

  @override
  int get hashCode => Object.hash(item, party);

  @override
  String toString() => 'StockInfoRoute(item: $item, party: $party)';
}
