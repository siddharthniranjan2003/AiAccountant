import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window.open')
external JSObject? _windowOpen(JSString url, JSString target, JSString features);

/// Named target, so there is only ever ONE Stock Info window. Passing a name
/// instead of '_blank' makes the browser reuse the window already carrying it
/// rather than spawning another; if the user closed it, the browser creates a
/// fresh one, so no bookkeeping is needed on our side.
const _stockInfoWindowName = 'replara_stock_info';

/// Web: opens [url] in a separate popup browser window rather than a tab —
/// passing width/height window features makes the browser create a real window.
///
/// On a reused window the features are ignored (they only apply at creation) and
/// the navigation is same-document, since these URLs differ only in the hash —
/// see routeChanges in stock_info_route_web.dart for the other half. The
/// returned handle is focused so the window comes to the front either way.
Future<void> openPopupWindow(String url) async {
  final handle = _windowOpen(
    url.toJS,
    _stockInfoWindowName.toJS,
    'popup=yes,width=1280,height=800'.toJS,
  );
  handle?.callMethod<JSAny?>('focus'.toJS);
}
