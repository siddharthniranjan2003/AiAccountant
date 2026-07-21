import 'package:url_launcher/url_launcher.dart';

/// Non-web fallback: no popup windows exist, so open [url] the default way
/// (external browser).
Future<void> openPopupWindow(String url) => launchUrl(Uri.parse(url));
