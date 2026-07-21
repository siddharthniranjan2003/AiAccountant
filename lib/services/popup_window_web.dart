import 'dart:js_interop';

@JS('window.open')
external JSAny? _windowOpen(JSString url, JSString target, JSString features);

/// Web: opens [url] in a separate popup browser window rather than a tab —
/// passing width/height window features makes the browser create a real window.
Future<void> openPopupWindow(String url) async {
  _windowOpen(url.toJS, '_blank'.toJS, 'popup=yes,width=1280,height=800'.toJS);
}
