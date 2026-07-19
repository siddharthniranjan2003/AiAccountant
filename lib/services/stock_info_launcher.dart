import 'package:url_launcher/url_launcher.dart';

/// Opens the standalone Stock Info screen in a new browser tab.
///
/// The app uses Flutter web's default *hash* URL strategy, so the route lives
/// in the URL fragment. We point a new tab at
/// `<app>#/stock-info?item=<name>&party=<name>` (party is added only when the ⓘ
/// was clicked on a sale invoice); [main.dart] reads that fragment on boot and
/// renders `StockInfoScreen` instead of the auth gate. Item + party are passed
/// through the URL so the new (fresh) app instance can query without any shared
/// in-memory state.
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
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }
}
