import 'package:sentry_flutter/sentry_flutter.dart';

/// Reports a *handled* error to Sentry without changing control flow.
///
/// Use at catch sites that would otherwise swallow a failure silently
/// (`catch (_) {}`, `debugPrint`-only, or a snackbar with no telemetry) — most
/// notably the app's direct Supabase calls, which (unlike the backend HTTP
/// calls in ApiClient) are not otherwise visible to Sentry when caught locally.
///
/// [operation] is a stable, greppable label, e.g. `supabase.push_queue.refresh`.
/// No-op when Sentry is disabled (no DSN), so call sites stay behaviour-neutral.
void reportHandledError(
  String operation,
  Object error, {
  StackTrace? stackTrace,
  Map<String, dynamic>? context,
}) {
  Sentry.captureException(
    error,
    stackTrace: stackTrace,
    withScope: (scope) {
      scope.level = SentryLevel.error;
      scope.setTag('operation', operation);
      if (context != null && context.isNotEmpty) {
        scope.setContexts('details', context);
      }
    },
  );
}
