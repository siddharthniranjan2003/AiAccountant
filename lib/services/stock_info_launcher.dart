import 'popup_window_stub.dart'
    if (dart.library.js_interop) 'popup_window_web.dart';

/// Shows the standalone Stock Info screen in its own browser window (popup, not
/// a tab; falls back to the default browser on non-web platforms).
///
/// There is only ever ONE such window: on web the popup carries a fixed name, so
/// a second call retargets and focuses the window already open instead of
/// stacking another one on top (see popup_window_web.dart).
///
/// The app uses Flutter web's default *hash* URL strategy, so the route lives
/// in the URL fragment. We point the window at
/// `<app>#/stock-info?item=<name>&party=<name>` (party is added only when the ⓘ
/// was clicked on a sale invoice). A cold window is built from that fragment by
/// [main.dart]; an already-open one sees the fragment change and updates in
/// place without reloading — `StockInfoRoute` parses it for both paths.
class StockInfoLauncher {
  const StockInfoLauncher._();

  static Future<void> open({required String itemName, String? partyName}) async {
    final base = Uri.base;
    // Only carry a real party through (sale invoices); '—' is the sheet's
    // unknown-party placeholder.
    final party = partyName?.trim() ?? '';
    final partyQuery = (party.isNotEmpty && party != '—')
        ? '&party=${Uri.encodeComponent(party)}'
        : '';
    final url =
        '${base.origin}${base.path}#/stock-info?item=${Uri.encodeComponent(itemName)}$partyQuery';
    await openPopupWindow(url);
  }
}
