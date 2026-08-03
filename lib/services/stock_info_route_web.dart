import 'dart:async';
import 'dart:js_interop';

import 'stock_info_route.dart';

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

/// Web: emits whenever the URL fragment changes to a stock-info route.
///
/// Retargeting the Stock Info window is a `window.open` at the same document
/// with a different hash (see popup_window_web.dart). Because only the fragment
/// differs, the browser treats it as a same-document navigation: it fires
/// `hashchange` and does NOT reload the page — which is what lets the already
/// booted window update in place instead of re-running the whole Flutter app.
///
/// Fragments that aren't stock-info routes are dropped, so a stray hash change
/// can't blank the window. Broadcast so more than one listener is allowed, and
/// never closed: it lives as long as the window does.
Stream<StockInfoRoute> get routeChanges => _controller.stream;

final StreamController<StockInfoRoute> _controller = _listen();

StreamController<StockInfoRoute> _listen() {
  final controller = StreamController<StockInfoRoute>.broadcast();
  _addEventListener(
    'hashchange'.toJS,
    ((JSAny _) {
      final route = StockInfoRoute.parse(Uri.base.fragment);
      if (route != null) controller.add(route);
    }).toJS,
  );
  return controller;
}
