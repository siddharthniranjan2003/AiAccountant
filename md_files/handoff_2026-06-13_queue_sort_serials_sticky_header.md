# Handoff — 2026-06-13 — Multi-env verify, queue sort, item serials, sticky header

Covers everything from the last compact to now. Continues the earlier handoffs
(most recently `handoff_2026-06-12_multienv_config_endpoints_sha.md`). Read that
one for config/endpoint/SHA ground truth; this doc adds the **multi-flavor build
reference (now verified)** plus three code changes (queue sort, item serial
numbers, pinned items header).

Branch: `project_reorg`. **Nothing committed** since `711fd3c`. All work below is
in the working tree.

---

## 0. Multi-environment build/deploy — VERIFIED against the repo

The user supplied a command reference; I checked it against the code and it is
**accurate and fully wired**. Key facts:

- **Firebase projects (3 environments)** — `.firebaserc`:
  - `prod` / `default` → `aiaccountant-b60ed`
  - `testing` → `tallybridge-testing-env-636d4`
  - `deployment` → `tallybridge-deployment-env`
- **Firebase CLI accounts:** `testing.riplara@gmail.com`, `deployment.riplara@gmail.com`
  (plus the original `siddharthniranjan2003@gmail.com`).
- **Android flavors** (`android/app/build.gradle.kts`, dimension `env`):
  `staging`, `deployment`, `prod`. NOTE: the testing flavor is named **`staging`**
  because Gradle forbids flavor names starting with "test". Same `applicationId`
  for all (not side-by-side installable).
- **Per-flavor `google-services.json`** present: `src/staging/`, `src/deployment/`,
  `src/prod/`. Root `android/app/google-services.json` remains only as a fallback.
- **`firebase_options.dart` is flavor-aware:** reads `FLAVOR` via
  `String.fromEnvironment` (default `testing`) and selects the matching Firebase
  project (testing-env / deployment-env / aiaccountant-b60ed).

**One `FLAVOR` key drives everything:** `--dart-define-from-file=env/<flavor>.json`
sets `FLAVOR`, which selects (a) the Firebase project in `firebase_options.dart`
and (b) the Supabase/backend creds in `config.dart`. On Android, the `--flavor`
flag additionally selects the native `google-services.json`.

### Command reference (run lines in order; PowerShell, no `&&`)

**TESTING**
```
flutter build web --dart-define-from-file=env/testing.json
firebase deploy --only hosting --project testing --account testing.riplara@gmail.com
# → https://tallybridge-testing-env-636d4.web.app

flutter build apk --flavor staging --dart-define-from-file=env/testing.json
# → build\app\outputs\flutter-apk\app-staging-release.apk
```

**DEPLOYMENT**
```
flutter build web --dart-define-from-file=env/deployment.json
firebase deploy --only hosting --project deployment --account deployment.riplara@gmail.com
# → https://tallybridge-deployment-env.web.app

flutter build apk --flavor deployment --dart-define-from-file=env/deployment.json
# → build\app\outputs\flutter-apk\app-deployment-release.apk
```

Reminders:
- `flutter build web` defaults to release — no `--release` needed.
- **Build + its deploy must stay paired.** `build/web` is a single shared output
  dir (no flavor in the path); always build immediately before its own deploy, or
  you'll ship the wrong bundle to a site.
- Deployment login needs Firebase setup finished first: Phone provider + SMS
  region policy → Allow → India, and the deployment backend's
  `FIREBASE_SERVICE_ACCOUNT_B64` set. (Console/backend side — not in the repo.)

---

## 1. Config: source of truth (clarification, no code change)

- **For a flavored build, `env/<flavor>.json` is the source of truth** for Supabase
  / backend / API keys / endpoints — dart-defines override the `config.dart`
  `defaultValue`s. To change **testing** creds → edit `env/testing.json`.
- **`config.dart` is the reader, not redundant.** Dart can't read the JSON at
  runtime; `--dart-define-from-file` injects values at *compile time*, reachable
  only via `String.fromEnvironment`. `config.dart` is the single place that makes
  those calls + names keys + provides typed accessors + bare-build defaults.
- **`config.dart` is consumed in 4 files:** `main.dart` (Supabase init),
  `api_client.dart` (`backendBaseUrl`, `mrpApiKey`), `app_shell.dart` (sale/purchase
  parse URLs), `voucher_detail_sheet.dart` (`activateUrl`, `activateApiKey`).
  `Config.backendApiKey` is **unused** (report x-api-key uses `mrpApiKey`).
- **Firebase creds are NOT in env files** — only `FLAVOR` (which *selects* the
  project). Firebase config lives in `firebase_options.dart` (web) +
  `src/<flavor>/google-services.json` (Android).

---

## 2. CHANGE A — Queue sorted newest-first by timestamp (Option B)

**Goal:** within each day group on the queue screen, order rows by real timestamp
(newest first), for **both sale and purchase**. Previously rows were just
`[supabase rows (created_at desc), …seed rows appended]` grouped by day label,
which left demo rows stranded mid-list with non-sequential serials.

**Approach (no backend/DB change — `created_at` was already fetched):**
- `lib/core/models.dart` — added `final int sortKey` (epoch millis, default `0`)
  to `QueueEntry`; carried through `copyWith`. (Used `int`, not `DateTime`, so the
  `const` seed entries still compile — mirrors `HistoryEntry.sortKey`.)
- `lib/data/push_queue_service.dart` — `rowToEntry` now sets
  `sortKey: createdAt.millisecondsSinceEpoch` (reusing the `DateTime` it already
  parsed at line ~114). Realtime insert/update payloads carry `created_at` too, so
  live rows sort correctly.
- `lib/features/queue/queue_screen.dart` — `_visibleRows` now sorts the
  tab-filtered list **descending by `sortKey`** (`..sort((a,b) => b.sortKey.compareTo(a.sortKey))`);
  `build` computes it once and feeds both `_groupRows` and the serial lookup.
- `lib/data/seed_data.dart` — **removed the 4 demo sale rows** (`sale_abc`,
  `sale_def`, `sale_xyz`/XYZ Mart, `sale_mno`/MNO Supply). The 4 demo **purchase**
  rows remain in `seedQueueEntries` but are **never loaded** (`app_shell.dart:49`
  only pulls sale seed into `_saleEntries`) — dead but harmless; left untouched to
  avoid unrelated churn.

**Result:** sort happens on the flat list before grouping + serial assignment, so
within-day order, day-header order (today no longer sinks), and serial numbers are
all consistent. Applies to both tabs (`_visibleRows` filters by `_activeType` then
sorts regardless of type).

---

## 3. CHANGE B — Serial number column in the voucher items table

**Goal:** number each item line (`1, 2, 3…`) in the voucher detail sheet, for both
sale and purchase. All in `lib/features/queue/voucher_detail_sheet.dart`:
- Added `const double _kSerialColW = 30;` and folded it into `_kItemsTableW`
  (keeps mobile horizontal-scroll width correct).
- Added a `#` cell to the items column header (before `Item`).
- Added `final int serialNumber` (default 0) + constructor param to `_SheetItemRow`;
  passed `serialNumber: i + 1` at the call site; rendered as a muted, top-aligned
  number as the row's first cell.

The items table is type-agnostic (one `_SheetItemRow` renders sale and purchase),
so the column shows for both, in view and edit modes.

---

## 4. CHANGE C — Pinned ("sticky") items column header

**Problem:** the voucher detail sheet body was one `ListView`, so the items column
header (`# Item Qty Disc Rate Amount`) scrolled out of view.

**Fix (all in `voucher_detail_sheet.dart`):** converted the summary body from
`ListView` to **`CustomScrollView`** and made the column header a pinned sliver:
- Lifted the four blocks into locals: `vendorCard`, `itemsHeader`, `itemsBody`,
  `chargesCard` (plus `titleStyle`). The big `_SheetItemRow` loop + all callbacks
  are unchanged, now inside `itemsBody`.
- Added top-level `class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate`
  (fixed extent, `min == max`).
- Slivers: `SliverToBoxAdapter` (vendor card + "Items" title) → optional
  `SliverPersistentHeader(pinned: true)` with the items header → `SliverToBoxAdapter`
  (items body + charges). Padding split to reproduce the old `(16,16,16,32)`.
- **Header height** = `MediaQuery.textScalerOf(context).scale(12) * 1.7 + 18` so it
  accounts for the **web 1.4× TextScaler** (set globally in `main.dart:66`,
  web-only) and won't clip on web or mobile.

**Scope / deliberate limitation:**
- **Wide / web screens:** header is **pinned** (both sale & purchase).
- **Narrow / mobile screens:** header stays **inline** with the body inside the
  existing horizontal `SingleChildScrollView` (width `_kItemsTableW`). Reason: on
  mobile the table is wider than the screen and scrolls horizontally; a
  vertically-pinned header would desync from the body's horizontal offset
  (columns wouldn't line up). Pinning on mobile would need a synced horizontal
  scroll controller — not done. **Open question for the user: web-only pin OK, or
  implement the synced-controller mobile version too?**

`itemsHeader` is referenced in both the pinned sliver (wide) and the inline narrow
Column, but only one branch mounts per build (guarded by `wide`), so it's never
double-mounted.

---

## 5. Verification status

- `flutter analyze` — **clean, no issues** (full project) after all changes.
- **Not yet run / not verified at runtime:** no `flutter build` / deploy executed
  for any of these changes; sticky header + serials not visually confirmed in a
  running build. Recommend: build+deploy testing web and hard-refresh past the
  service worker, then eyeball the queue order, the `#` column, and the pinned
  header while scrolling.

---

## 6. Outstanding / next steps

- **Build + deploy** the testing web (and APK if needed) to see Changes A–C live;
  hard-refresh past the service worker.
- **Decide mobile sticky header** (§4 open question).
- Carried from prior handoff: `env/prod.json` still placeholder
  (`366926737745`, `_PROD_PENDING_CONFIRM`); deployment Firebase phone/SMS-region +
  backend `FIREBASE_SERVICE_ACCOUNT_B64` setup; `applicationId` still
  `com.example.aiaccountant`.
- **Commit** — nothing committed since `711fd3c`; the tree now has the multi-flavor
  config/env/firebase wiring plus Changes A–C.

---

## Files touched this session
- `lib/core/models.dart` — `QueueEntry.sortKey`
- `lib/data/push_queue_service.dart` — populate `sortKey`
- `lib/features/queue/queue_screen.dart` — sort `_visibleRows` newest-first
- `lib/data/seed_data.dart` — removed demo sale rows
- `lib/features/queue/voucher_detail_sheet.dart` — serial `#` column + pinned header
  (`CustomScrollView` + `_PinnedHeaderDelegate`)

## Carried constraints (still in force)
- Publishable/anon keys only in `config.dart`/env — **never a service-role key**;
  RLS required.
- Supabase MCP treated **read-only**; DB writes need explicit per-migration confirm.
- Web hosting per flavor (see §0); `android/key.properties` gitignored (keystore
  passwords).
- Push always sets `narration='Replara AI'`; purchase vendors = Sundry Creditors,
  sale customers = Sundry Debtors.
- Live client-data Supabase = `ztugwhevemibdrzqafyw` (the **deployment** flavor);
  testing = `yynuuysvjeipawzfbeme`.
