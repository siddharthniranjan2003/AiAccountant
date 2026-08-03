import 'stock_info_route.dart';

/// Non-web fallback: there is no browser window to retarget, so a Stock Info
/// screen is only ever created with the item it was built for and this stream
/// never fires. Keeping it inert (rather than absent) means the screen can
/// subscribe unconditionally, with no `kIsWeb` branch.
Stream<StockInfoRoute> get routeChanges => const Stream<StockInfoRoute>.empty();
