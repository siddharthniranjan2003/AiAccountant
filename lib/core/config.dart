/// Single source of truth for all network endpoints and API keys.
///
/// Values are injected per-environment at build time via
/// `--dart-define-from-file=env/<flavor>.json` (see `env/testing.json`,
/// `env/deployment.json`, `env/prod.json`). The defaults below match the
/// **testing** env so a bare build still runs. To switch environments, choose
/// the matching `--flavor` + env file; do NOT hardcode a different URL here.
/// (Publishable/anon keys are safe to ship only with RLS enabled; never put a
/// service-role key in this file.)
class Config {
  Config._();

  // ── Supabase (client connection) ──────────────────────────────────────────
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yynuuysvjeipawzfbeme.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl',
  );

  // ── Main backend (Cloud Run) — used by ApiClient (reports, etc.) ──────────
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue:
        'https://tallybridge-backend-828647628834.asia-south1.run.app',
  );
  static const String backendApiKey = String.fromEnvironment(
    'BACKEND_API_KEY',
    defaultValue: 'sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl',
  );
  // x-api-key sent with report (reorder-levels) requests via ApiClient.
  static const String mrpApiKey = String.fromEnvironment(
    'MRP_API_KEY',
    defaultValue: 'sb_publishable_IRsM8wDF6w9OyiPegwB2cw_a9aqW9lt',
  );

  // ── Push-to-Tally activate endpoint (separate Cloud Run service) ──────────
  static const String activateUrl = String.fromEnvironment(
    'ACTIVATE_URL',
    defaultValue:
        'https://tallybridge-backend-828647628834.asia-south1.run.app/api/sync/push-queue/activate',
  );
  static const String activateApiKey = String.fromEnvironment(
    'ACTIVATE_API_KEY',
    defaultValue: 'sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl',
  );

  // ── Crash reporting (Sentry) ──────────────────────────────────────────────
  // Empty by default => Sentry is a no-op and the app behaves exactly as before.
  // Fill SENTRY_DSN per env (env/<flavor>.json) from your Sentry "flutter"
  // project. The environment tag reuses the existing FLAVOR define.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );
  static const String sentryEnvironment = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'testing',
  );
  static const double sentryTracesSampleRate = 1.0;

  // ── Document parsing service (Cloud Run) — raw PDF upload ─────────────────
  static const String saleParseUrl = String.fromEnvironment(
    'SALE_PARSE_URL',
    defaultValue:
        'https://tallybridge-parsing-828647628834.asia-south1.run.app/?type=sale&push=queue',
  );
  static const String purchaseParseUrl = String.fromEnvironment(
    'PURCHASE_PARSE_URL',
    defaultValue:
        'https://tallybridge-parsing-828647628834.asia-south1.run.app/docstrange?purchase=all&source=runpod',
  );
}
