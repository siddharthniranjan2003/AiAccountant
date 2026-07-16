# Handoff — 2026-06-14 — Concurrent scan loading indicators in the queue

Covers everything from the last compact to now. Continues the earlier handoffs
(most recently `handoff_2026-06-13_queue_sort_serials_sticky_header.md`). This doc
adds **one feature**: dumb "Processing…" loading rows in the queue while scanned
PDFs are being parsed.

**Branch:** `feature/scan-loading-indicators` (created this session off the
working tree). **Nothing committed** — all work is uncommitted in the tree. Last
commit is still `711fd3c`.

---

## 0. What the user asked for

> "lets handle concurrent request and lazy loading and showing that in ui … discuss"

After discussion this resolved to a concrete, scoped feature:

- When the user sends sale/purchase PDFs, show **N plain "loading" rows** at the
  top of the matching queue tab (Sale loaders in Sale tab, Purchase loaders in
  Purchase tab) while their parse HTTP requests are in flight.
- Remove each loader when its request settles.
- **"Plain dumb loading"** — no progressive content, no per-item fill. Just
  spinner + "Processing…".

### Design decisions locked with the user (important)
- **Surface = in-queue rows, NOT a toast stack.** (The pre-existing but unwired
  `ToastStack`/`ToastEntry`/`ToastKind` scaffolding in `lib/shared/toast_stack.dart`
  was considered and rejected for this — user wanted the indicator *inside* the
  queue screen.)
- **Loader removal = Option A:** a loader is tied to its parse **HTTP request** —
  shown while the POST is in flight, removed when it resolves (success OR error).
  **No `job.id` correlation** with the eventual realtime row (that remains the
  known gap — see `sale-response-needs-job-id` memory). Accepted trade-off: a
  brief cosmetic gap/overlap between a loader clearing and its realtime row
  appearing.
- **Keep the auto-modal sheet** on scan exactly as today. Loaders are purely
  additive; the scan flow is otherwise untouched.
- **No `ScanJob`/`ChangeNotifier` class.** Dumb loading only needs a per-type
  count, so the "concurrency manager" is just two ints in the existing shell
  state. Upgradeable later.

---

## 1. How the scan/parse flow works (context for the change)

- Camera tab → `_openTaggedCameraFlow` (`app_shell.dart`) → ML Kit
  `DocumentScanner.scanDocument()` returns **one** PDF per invocation (its
  `pageLimit: 20` is *pages of one document* → one voucher, not multiple files).
- → `_uploadAndShowResult` fires **one** `_parseDocument` POST to the Cloud Run
  parse URL and opens a `VoucherDetailSheet` (via `unawaited(showModalBottomSheet)`)
  that consumes the in-flight future.
- The durable queue rows are fed **independently** by Supabase realtime
  (`push_queue_service.dart`) — the backend inserts a `push_queue` row after
  parsing. So multiple scans already land in the queue regardless of the sheet.
- The sheet already handles the future's errors itself:
  `voucher_detail_sheet.dart:217` → `pendingPayload!.then(...).catchError(...)`.

There is **no** share-intent / multi-file batch import path — the scanner is the
only way a PDF enters the app.

---

## 2. What was implemented (3 files)

### NEW: `lib/features/queue/queue_loading_tile.dart`
`QueueLoadingTile` — stateless. Mirrors `QueueRowTile`'s padding + top-border so
it lines up under `QueueTableHeader`. A small `CircularProgressIndicator`
(strokeWidth 1.8, `AppPalette.muted`) in the 22-wide leading slot + muted
"Processing…" text. No party, no time, no amount. Takes `isFirst` for the
top-border rule.

### `lib/features/shell/app_shell.dart`
- Added two counters to `_AccountantShellState` (live above the `IndexedStack`
  so loaders survive tab navigation):
  ```dart
  int _saleLoadingCount = 0;
  int _purchaseLoadingCount = 0;
  ```
- In `_uploadAndShowResult`, right after `final future = _parseDocument(...)`,
  added `_trackScanJob(type, future);` (same future still passed to the sheet —
  single request, two listeners).
- Added `_trackScanJob(TransactionType type, Future<dynamic> future)`:
  increments the matching counter via `setState`, `await future` inside
  `try/catch(_)` (errors swallowed — the **sheet** owns real error handling, so
  this tracking path stays free of uncaught async errors), then decrements in
  `finally` (guarded by `mounted`). This is Option A: loader lifetime == HTTP
  request lifetime.
- In `build`, passed to `QueueScreen`:
  ```dart
  loadingCount: _queueTabIndex == 0 ? _saleLoadingCount : _purchaseLoadingCount,
  ```

### `lib/features/queue/queue_screen.dart`
- Imported `queue_loading_tile.dart`.
- Added `final int loadingCount;` (default `0`) to the widget + constructor.
- In `build`, **before** the `for (final group in groupedRows.entries)` loop in
  the `ListView`, added a guarded block: when `widget.loadingCount > 0`, render a
  container with the **same `BoxDecoration` as the day-group container** holding
  `loadingCount` `QueueLoadingTile`s (`isFirst: index == 0`), + a trailing
  `SizedBox(height: 14)`. Puts loaders at the very top, above the "Today" group.

**No changes** to `models.dart`, `push_queue_service.dart`, the realtime path, or
the backend.

---

## 3. Verification done

- `flutter analyze` on the three touched files → **"No issues found!"**
- User built the **testing APK** (`flutter build apk --flavor staging
  --dart-define-from-file=env/testing.json`) and tested on-device.

### Observed: "I sent two purchase PDFs but only ONE 'Processing…' row showed"
**This is expected, not a bug.** The loaders work (one *did* render). You only
ever see one because the sends are **serial, not concurrent**, and a loader only
lives while its HTTP request is in flight (Option A):
1. Scan PDF 1 → loader=1, modal opens, request 1 starts.
2. Dismiss sheet → re-open camera → scan PDF 2 (several taps + ML Kit UI = a few
   seconds).
3. By the time request 2 starts, request 1 has **already finished** → its loader
   was removed → count is back to 1.

So two requests are essentially never in flight at the same instant under the
current one-PDF-per-scan + auto-modal flow → the loader is realistically always a
count of 1. The render loop itself is correct (`for index < loadingCount`); the
count just never reaches 2.

---

## 4. Outstanding / next step (the real decision)

To make the concurrency **actually visible** (N loaders at once), one of:

1. **True rapid-fire sending (recommended next step):** stop blocking on the
   modal sheet between scans so the user can fire scan-after-scan and multiple
   parses are genuinely in flight together. This is the *"drop/bypass the
   auto-modal"* change the user **deferred** ("for now leave the auto-modal").
   Without it, the flow is inherently serial and the loader stays at 1.
   - I offered to implement this on the branch; **user has not yet confirmed.**
2. **Batch / multi-file import:** pick or share multiple PDFs in one action and
   spawn one job per file. Needs a multi-file picker / share-intent path (the ML
   Kit scanner can't do it) — a bigger change.

Also still open from before:
- **`job.id` correlation** (backend) would let a loader seamlessly *become* its
  realtime row (Option B), removing the cosmetic gap/overlap. Known gap.
- **Commit** — nothing committed on this branch yet.
- Build/deploy **web** if the indicator is wanted there too (only APK tested).

---

## Files touched this session
- `lib/features/queue/queue_loading_tile.dart` — **new** loading tile.
- `lib/features/shell/app_shell.dart` — `_saleLoadingCount`/`_purchaseLoadingCount`,
  `_trackScanJob`, pass `loadingCount` to `QueueScreen`.
- `lib/features/queue/queue_screen.dart` — `loadingCount` param + render loaders
  at top of the active tab's list.

## Carried constraints (still in force)
- Publishable/anon keys only in `config.dart`/env — **never a service-role key**;
  RLS required.
- Supabase MCP treated **read-only**; DB writes need explicit per-migration confirm.
- Push always sets `narration='Replara AI'`; purchase vendors = Sundry Creditors,
  sale customers = Sundry Debtors.
- Live client-data Supabase = `ztugwhevemibdrzqafyw` (deployment flavor); testing
  = `yynuuysvjeipawzfbeme`. Web hosting = Firebase `aiaccountant-b60ed` (prod) /
  per-flavor (testing/deployment).
