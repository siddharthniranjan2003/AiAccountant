# Handoff — 2026-06-12 — Multi-env config, endpoints, mrpApiKey, SHA fingerprints

Covers everything from the last compact to now. Continues the earlier handoffs
(`handoff_2026-06-11_client_sale_rpc_report_auth_spreadsheet.md` and the four
before it). Read this first for the *current* config/endpoint truth — values
have changed since the 2026-06-11 doc.

---

## 0. Ground truth (current)

- **App:** Flutter (Android + Web), "AI Accountant". Scans invoices → Cloud Run
  parse → Supabase → push vouchers to Tally.
- **Deployed web URL:** **https://aiaccountant-b60ed.web.app** (Firebase
  Hosting project **`aiaccountant-b60ed`**). Deploy = `firebase deploy --only
  hosting --project aiaccountant-b60ed`, serves `build/web`.
- **Firebase / Auth** lives in `lib/firebase_options.dart` → project
  `aiaccountant-b60ed` (web + android). This is **separate** from the
  Supabase/backend creds in `lib/core/config.dart`.
- **Two publishable keys in play** (anon/x-api-key; RLS-protected, safe to ship;
  never a service-role key):
  - `sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl` — testing/prod key.
  - `sb_publishable_IRsM8wDF6w9OyiPegwB2cw_a9aqW9lt` — old/client (deployment)
    key, **also currently used as `mrpApiKey` in every flavor** (see §2).

---

## 1. Multi-environment config (the big change this session)

### Evolution during the session (so you understand the churn)
1. `config.dart` was flat `static const` (testing).
2. Converted to `String.fromEnvironment(KEY, defaultValue: <testing>)` +
   `env/*.json` + `--dart-define-from-file` + per-env build scripts.
3. User asked "what problem does this solve" / "config.dart should be only
   source of truth" → reverted to flat `static const`, deleted `env/` and
   `build_prod.ps1`, simplified `build_test.ps1`.
4. **User then re-introduced the env approach themselves** and expanded it to
   **3 flavors**. That is the CURRENT state below.

### Current state — `lib/core/config.dart`
Every value is `String.fromEnvironment('KEY', defaultValue: <testing value>)`.
A bare `flutter build` uses the testing defaults; a build with
`--dart-define-from-file=env/<flavor>.json` overrides them. Keys:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BACKEND_BASE_URL`, `BACKEND_API_KEY`,
`MRP_API_KEY`, `ACTIVATE_URL`, `ACTIVATE_API_KEY`, `SALE_PARSE_URL`,
`PURCHASE_PARSE_URL`.

### The three env files (`env/`)
| flavor | file | Supabase | Backend host (Cloud Run project #) | key used |
|---|---|---|---|---|
| **testing** | `env/testing.json` | `yynuuysvjeipawzfbeme` | `…-828647628834…` | `c2Cov2…` (mrp=`IRsM8…`) |
| **deployment** | `env/deployment.json` | `ztugwhevemibdrzqafyw` | `…-822222628942…` | `IRsM8…` (all incl. mrp) |
| **prod** | `env/prod.json` | `yynuuysvjeipawzfbeme` (placeholder) | `…-366926737745…` (placeholder) | `c2Cov2…` (mrp=`IRsM8…`) |

- `config.dart` defaults == **testing** values (host `828647628834`).
- `env/prod.json` has a `_PROD_PENDING_CONFIRM` note: backend/Supabase are
  placeholders (the old `366926737745` config); replace with real prod targets
  once confirmed. Its Firebase (`FLAVOR=prod`) is correctly `aiaccountant-b60ed`.
- Each file carries a `FLAVOR` key for identification.

### ⚠️ Wiring gaps to be aware of
- **`build_test.ps1` does NOT use any env file.** It runs a bare
  `flutter build web --release` (so it builds the `config.dart` testing
  defaults) then deploys to `aiaccountant-b60ed`. Its header comment still says
  "credentials come from config.dart (single source of truth)" — **stale**
  relative to the reintroduced env-file approach.
- **No `build_deployment.ps1` / `build_prod.ps1` exist.** Only testing has a
  script, and it doesn't pass `--dart-define-from-file`. To actually build a
  flavor you currently must run, e.g.:
  `flutter build web --release --dart-define-from-file=env/deployment.json`
- `config.dart` comment mentions `--flavor`, but Flutter **web** has no real
  flavor mechanism — `--dart-define-from-file` is what does the work. Android
  flavors are not set up in `build.gradle.kts`.

---

## 2. mrpApiKey → report `x-api-key` (code change made this session)

- User added `Config.mrpApiKey` (default `sb_publishable_IRsM8wDF6w9OyiPegwB2cw…`).
- **Change applied:** `lib/services/api_client.dart` `_headers()` now sends
  `'x-api-key': Config.mrpApiKey` (was `Config.backendApiKey`).
- `_headers()` is shared by `ApiClient.get`/`getRaw`/`post`, but **only
  `getRaw` is called, and only by the report screen** — so this affects exactly
  the **report (reorder-levels)** requests.
- `Config.backendApiKey` is now **unused** in code (left in place intentionally;
  user keeps both keys).
- Reason: the report ("MRP") endpoint expects the `IRsM8…` key; using
  `backendApiKey` (`c2Cov2…`) was the suspected cause of the old "Unauthorized".

---

## 3. Endpoint reference (current, testing defaults)

All hosts below are the **testing** project `828647628834`; deployment uses
`822222628942`, prod placeholder uses `366926737745`.

- **Sale PDF parse** — `app_shell.dart` → `_parseDocument`:
  `https://tallybridge-parsing-828647628834.asia-south1.run.app/?type=sale&push=queue`
  `POST`, body = raw PDF bytes, header `Content-Type: application/pdf`, no auth.
- **Purchase PDF parse**:
  `https://tallybridge-parsing-828647628834.asia-south1.run.app/docstrange?purchase=all&source=runpod`
  Same POST shape. (Note: sale hits `/`, purchase hits `/docstrange` — different paths & query.)
- **Push-to-Tally (button)** — `voucher_detail_sheet.dart:711`, `_activateUrl`:
  `https://tallybridge-backend-828647628834.asia-south1.run.app/api/sync/push-queue/activate`
  `POST`, headers `Content-Type: application/json` + `x-api-key: <activateApiKey>`,
  body = JSON voucher payload (`narration` = push narration). No Firebase token.
- **Report (reorder-levels)** — `report_screen.dart` → `ApiClient.getRaw`:
  `GET {BACKEND_BASE_URL}/api/sync/reorder-levels/{R#}?company_name=K V ENTERPRISES&format=csv`
  Headers: `x-api-key: <mrpApiKey>` + (if logged in) `Authorization: Bearer <Firebase ID token>`.
  `company_name` is hardcoded `K V ENTERPRISES`. Response = CSV. `R1`–`R7` map to
  report keys act_now / hero_sku_health / dead_capital / buying_mistakes /
  wind_down / risk_watch / full_portfolio_health.

---

## 4. Which requests carry the Firebase credential

- The Firebase **ID token** (`Authorization: Bearer …` from
  `FirebaseAuth.instance.currentUser?.getIdToken()`) is attached in **exactly one
  place**: `api_client.dart:_headers()` (lines 11/15).
- Since `ApiClient` is only used by the report screen, **reports are the only
  Firebase-authenticated calls.** Token is conditional (`if token != null`).
- Parse (sale/purchase), push-to-Tally activate, and all Supabase queries do
  **not** send the Firebase token. Supabase calls use the anon key.
- Probe earlier this session: the report endpoint returned **HTTP 200 with
  `x-api-key` only (no token)** on testing backend `366926737745` — i.e. the
  backend gates on `x-api-key`, not the Firebase project. So Firebase Auth choice
  doesn't affect backend calls; it only governs who can log in. (Re-verify on
  `828647628834` / `822222628942` if needed.)

---

## 5. "Unauthorized" report error (recap, no code change beyond §2)

- Message `Failed to load report: Exception: Unauthorized` = backend returned
  **HTTP 401** (`getRaw` throws on 401, discards body).
- DevTools earlier proved the request was well-formed (valid Bearer + x-api-key +
  correct company + CORS 204). Root cause was **authorization / wrong account**;
  resolved by logging in with the right credentials. The §2 mrpApiKey switch is
  the durable fix for the key side.

---

## 6. Android signing & Firebase registration

- **Android package name (`applicationId`):** `com.example.aiaccountant`
  (`android/app/build.gradle.kts:36`; `namespace` line 21 matches). Still the
  Flutter **default** — there's a `TODO` to change it. If you rename before
  release, do it BEFORE registering the Firebase Android app + fingerprints.
- **Release signing:** `android/key.properties` (gitignored) →
  `storeFile=upload-keystore.jks`, `keyAlias=upload`,
  `storePassword=keyPassword=AiAcct#2026!kv`. `build.gradle.kts` loads it if
  present, else falls back to debug signing.
- **SHA fingerprints (extracted/generated this session):**

  Release / upload key (`android/app/upload-keystore.jks`, alias `upload`):
  ```
  SHA-1:   E8:4E:8C:49:6C:35:5F:76:B2:71:97:1D:09:F8:C8:B2:85:38:9B:A0
  SHA-256: 53:37:61:7A:15:66:82:7C:B1:01:0B:74:5D:92:9C:E5:1E:67:AC:78:6D:D3:E7:F1:17:D1:C0:A3:26:02:26:9F
  ```
  Debug key (`~/.android/debug.keystore`, alias `androiddebugkey`) — **generated
  this session** (didn't exist before; standard debug params):
  ```
  SHA-1:   D7:F5:8B:27:FF:5E:8D:07:C4:09:20:4E:28:92:39:B0:99:E0:12:D3
  SHA-256: 2B:21:03:3D:35:A0:90:17:38:00:D6:A5:24:37:E7:01:D0:A0:4E:6E:73:AF:1B:AA:35:CD:8D:81:DB:72:E1:9F
  ```
  (`keytool` is at `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`;
  not on PATH.)
- **User is registering the Android app in a DIFFERENT Firebase project** (new
  one, for the new deployment/client). Register under package
  `com.example.aiaccountant`, add the 4 fingerprints (both keys × SHA1/256), and
  if shipping via Play Store also add the **Play App Signing** SHAs from Play
  Console (Google re-signs — can't be generated locally).

---

## 7. Build / deploy facts

- Testing web build+deploy ran twice successfully this session (exit 0). Release
  web build ≈ 68–70s; Hosting URL `https://aiaccountant-b60ed.web.app`.
- Service worker caches aggressively → **hard-refresh** after deploy.
- Android APK has NOT been rebuilt for any of the web/DB changes.

---

## 8. Outstanding / next steps

- **Decide the env-build workflow:** either add `build_deployment.ps1` /
  `build_prod.ps1` that pass `--dart-define-from-file=env/<flavor>.json`, or make
  `build_test.ps1` pass `env/testing.json`. Right now only a bare testing build
  is scripted and its comment is stale.
- **Fill in `env/prod.json`** real backend/Supabase (currently placeholder
  `366926737745`, flagged via `_PROD_PENDING_CONFIRM`).
- **New Firebase project** for deployment: register Android app, add SHA
  fingerprints (§6), add the new hosting domain to **Authorized domains** if auth
  is reused, re-download `google-services.json`.
- Confirm push-to-Tally works against the deployment/prod backends (only report
  endpoint was probed for the x-api-key-only behavior).
- Consider renaming `applicationId` off `com.example.…` before release.
- Nothing committed since `711fd3c` on branch `project_reorg`.

---

## Carried from prior handoffs (still relevant)
- Live client-data Supabase = `ztugwhevemibdrzqafyw` (now the **deployment**
  flavor); sale-item RPC `get_sale_items_for_party` was fixed there (party filter
  + JOIN; ~0.95s). Optional functional index
  `idx_vouchers_lower_party` not yet applied.
- Push always sets `narration='Replara AI'`; purchase vendors = Sundry Creditors,
  sale customers = Sundry Debtors.
- Supabase MCP treated read-only; DB writes need explicit per-migration confirm.
- `backend/` folder is reference/source only — untouched.
