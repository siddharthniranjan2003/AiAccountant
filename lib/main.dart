import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'features/auth/auth_gate.dart';
import 'features/stock/stock_info_screen.dart';
import 'core/theme.dart';
import 'core/config.dart';
import 'data/stock_items_cache.dart';
import 'data/customers_cache.dart';
import 'data/vendors_cache.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Hot restart resets Dart state (so Firebase.apps reads empty) but leaves the
  // native [DEFAULT] app registered, so re-initializing throws
  // [core/duplicate-app]. The existing native app is valid, so swallow it.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
  );

  // Wrap the app so Sentry captures unhandled Flutter framework errors, async
  // (zone) errors, and native crashes. With an empty DSN the SDK is a no-op and
  // appRunner still launches the app normally.
  await SentryFlutter.init(
    (options) {
      options.dsn = Config.sentryDsn;
      options.environment = Config.sentryEnvironment;
      options.tracesSampleRate = Config.sentryTracesSampleRate;
      // uid is attached explicitly below; never auto-collect phone numbers/PII.
      options.sendDefaultPii = false;
    },
    appRunner: () {
      runApp(const AccountantApp());
      _wireSessionAndSentryUser();
    },
  );

  // TEMPORARY — Sentry smoke test. Run once with
  //   flutter run --dart-define-from-file=env/testing.json --dart-define=SENTRY_VERIFY=true
  // to confirm events reach the dashboard, then delete this block.
  if (const bool.fromEnvironment('SENTRY_VERIFY')) {
    await Sentry.captureException(
      Exception('Sentry verify — aiaccountant Flutter'),
      stackTrace: StackTrace.current,
    );
  }
}

// Drive the session caches off auth state (single source of truth): download
// on sign-in, clear on sign-out. Covers cold-start-with-session, login, and
// logout. The uid guard skips redundant reloads if the stream re-emits the
// same user. Also tags the Sentry scope with the signed-in uid so every event
// (crash or captured backend failure) is attributable to a user.
void _wireSessionAndSentryUser() {
  String? lastUid;
  FirebaseAuth.instance.authStateChanges().listen((user) {
    final uid = user?.uid;
    Sentry.configureScope(
      (scope) => scope.setUser(uid == null ? null : SentryUser(id: uid)),
    );
    if (uid == lastUid) return;
    lastUid = uid;
    if (uid != null) {
      StockItemsCache.instance.fetch();
      CustomersCache.instance.fetch();
      VendorsCache.instance.fetch();
    } else {
      StockItemsCache.instance.clear();
      CustomersCache.instance.clear();
      VendorsCache.instance.clear();
    }
  });
}

class AccountantApp extends StatelessWidget {
  const AccountantApp({super.key});

  static final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    StockItemsCache.scaffoldKey = _scaffoldKey;
    // The app uses hash-based web URLs, so a deep-linked route lives in the
    // fragment. When a new tab is opened at `#/stock-info?item=…` (from the ⓘ
    // on a voucher item row), render the standalone Stock Info page instead of
    // the auth gate — it's self-contained UI and needs no signed-in session.
    final route = Uri.parse(Uri.base.fragment);
    final Widget home = route.path == '/stock-info'
        ? StockInfoScreen(
            itemName: route.queryParameters['item'] ?? '',
            partyName: route.queryParameters['party'],
          )
        : const AuthGate();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Accountant',
      theme: buildAppTheme(),
      scaffoldMessengerKey: _scaffoldKey,
      // Web renders smaller than mobile, so bump all text 40% on web only.
      // Applies app-wide (routes + modal sheets sit under this MediaQuery).
      builder: (context, child) {
        if (!kIsWeb || child == null) return child ?? const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child,
        );
      },
      // SelectionArea makes displayed Text selectable/copyable (Flutter web
      // paints text to canvas, so it isn't selectable by default).
      // AuthGate reacts to sign-in/sign-out and, on cold start with no restored
      // Firebase session, silently re-authenticates from the saved number.
      home: SelectionArea(child: home),
    );
  }
}
