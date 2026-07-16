# Handoff — 2026-06-15 — Realtime-driven processing count (fixed) + backend async (PENDING)

Continues `handoff_2026-06-15_serial_send_queue_count.md`. Branch:
**`feature/scan-loading-indicators`**. HEAD = **`4cccbef`** (unchanged this session).
Everything below is **uncommitted** in the working tree.

---

## 0. TL;DR
- The "Processing…" **count badge now works** — it climbs to 2, 3… as you send scans
  and drains as each invoice lands. **Verified on device** (badge showed 2, held, two
  EMKAY rows landed).
- The fix is **client-only**: the count is driven by the **invoice row arriving via
  Supabase realtime**, NOT by the HTTP reply. A socket/HTTP error never decrements it.
- The **timer icon** is now a clock-style **filled pie** (white background) that sweeps
  clockwise over a minute and changes its whole colour at each 15s mark.
- **PENDING (next phase, NOT done):** the backend **async request–reply** refactor +
  **`job_id` correlation** + durability layers. See §5 — this is flagged as the next work.

---

## 1. Files changed this session (all uncommitted, on top of `4cccbef`)
- **`lib/data/scan_inflight_service.dart`** — NEW. Process-level singleton that owns the
  "processing" set and dispatch.
- **`lib/data/push_queue_service.dart`** — added `onRowInserted(type)` fired on realtime INSERT.
- **`lib/features/shell/app_shell.dart`** — uses the singleton; wires `onRowInserted` →
  `notifyInvoiceArrived`; removed all diagnostics.
- **`lib/features/queue/queue_loading_tile.dart`** — timer ring → clock-style filled pie,
  white track.

Commit **only these four** when ready. Do NOT sweep the pre-existing unrelated pile
(`config.dart`, `.env_clinet`, `env/`, backend deletions, ~20 other lib files).

`flutter analyze lib` → clean.

---

## 2. The bug and the chain of corrected hypotheses (so the next chat doesn't repeat them)
Symptom: sending two scans, the count badge stayed at **1**.

Hypotheses raised and **disproven**, in order:
1. ~~"Rate-matched: the 1st parse finishes before you send the 2nd."~~ — Disproven: parse
   takes ~105s, far longer than the gap between sends.
2. ~~"The 1st HTTP reply comes back fast and decrements early."~~ — **Disproven by a live
   curl test** (see §4): the HTTP reply takes **~105s**, not seconds.
3. ~~"The scanner destroys the isolate, wiping the singleton."~~ — Disproven: a `bornAt`
   "svc age" probe **grew** across scans (15s → 26s), so the isolate/singleton survived.
4. **Actual root cause:** the old code decremented the count on the **HTTP reply/error**.
   The app's `http.post` for an in-flight scan errors/drops within seconds (most likely the
   app backgrounding when the scanner opens), so the job was removed from the count **while
   the backend kept parsing** and the invoice still landed ~105s later via realtime. The
   HTTP reply is an unreliable, too-early signal — and it isn't even what the user asked
   for ("decrease the count when the invoice shows on purchase/sale").

---

## 3. The fix that shipped (client-only)
`ScanInFlightService` (singleton, `instance`) holds `_pending` scans. A scan is counted
from **send** until its **invoice row arrives**:

- `enqueue(type, pdfPath, url)` → add to `_pending`, `notifyListeners()`, fire `_send`.
- `_send` POSTs the PDF (300s timeout) **only to trigger the backend** — its reply/error is
  **logged, never decrements** the count.
- `notifyInvoiceArrived(type)` → removes the **oldest pending of that type**; called by the
  realtime INSERT on `push_queue` (`PushQueueService.onRowInserted`).
- 300s **safety net** clears a job whose invoice never arrives, so the badge can't stick.

`app_shell.dart` listens to the singleton (`addListener` → `setState`) and reads
`countFor` / `oldestStartFor`. The singleton lives outside the widget, so it survives shell
recreation.

**Verified:** `push_queue` IS in the `supabase_realtime` publication (checked via SQL), and
fresh scanned rows insert as `status='pending'` (active), so the INSERT event fires and the
count decrements.

**Known limitation of the stopgap (by design):**
- **Fuzzy correlation** — decrements "oldest of that type," not the specific scan (no
  `job_id` yet). Fine for single-user; a stray `push_queue` insert would mis-decrement.
- **Upload cut mid-body** — if the PDF never reaches the backend, no row lands → the 300s
  safety net clears it with no result.
Both are addressed by the PENDING backend work (§5).

---

## 4. Key measured facts (don't re-derive)
- **Live curl test** (exact app call: raw PDF POST, `Content-Type: application/pdf`) of
  `D:\Downloads\image sample\cp.pdf` to the purchase endpoint, two requests 15s apart:
  - REQ1: sent +0s, **done +105s, HTTP 200** (real parse, ~64.9 KB JSON).
  - REQ2: sent +15s, **done +114s, HTTP 200**. Both overlapped and **both succeeded — no
    stall** that run.
- So parse round-trip ≈ **105s** (cold can be longer). Hence the 300s safety net.
- **Parsing backend does NOT serialize / isn't a single worker**: `server/handler.py` uses
  `ThreadingHTTPServer`, no lock, Cloud Run default concurrency 80. (Earlier "single serial
  worker" framing was wrong.)
- Parse endpoints: purchase `…/docstrange?purchase=all&source=runpod` (Nanonets RunPod),
  sale `…/?type=sale&push=queue` (MiniCPM RunPod). Source: `D:\Desktop\TallyBridge\parsing`.

---

## 5. ⚠️ PENDING — next phase (backend + durability). NOT STARTED.
Discussed and scoped this session; **flagged here as the pending work.**

### 5a. Async request–reply (the root-cause backend fix — biggest win)
- **Now:** `parsing/server/handler.py` `do_POST` (line 1776) runs OCR → pipeline → push
  **synchronously**, holding the app's connection the full ~105s.
- **Change:** generate a `job_id`, **return `202 + job_id` in ~1s**, run the parse in a
  background worker, push the result to `push_queue` (already happens).
- **Cloud Run caveat:** background work after responding is CPU-throttled by default →
  needs **`--no-cpu-throttling`** (CPU-always-on; service already has `--min-instances=1`)
  **OR Cloud Tasks** (enqueue → worker endpoint). **Open choice: pragmatic vs scalable.**
- **Benefit:** app connection 105s → ~1s; robust to backgrounding/app-close; kills the
  "couldn't be processed" error class.

### 5b. `job_id` correlation (exact count, closes the long-standing gap)
- Express `/push-queue` **already returns `{ job: { id, status, created_at } }`**
  (`backend/src/routes/sync.ts:2299`).
- `push_queue` columns: `id, company_id, voucher_payload, status, error_message,
  tally_response, created_at, pushed_at, source_payload`. No dedicated correlation column,
  **but `source_payload` (jsonb) is free and already flows to the app** → stash a client
  `job_id` there (no schema migration).
- App: read `job_id` from the 202, match it on the realtime row → **exact** decrement,
  replacing the fuzzy "oldest of type." Do 5a + 5b together (same change).

### 5c. Durability layers (ranked)
1. Backend async 202 (5a) — root cause.
2. **Client durable queue + retry** — persist each scan `{pdf, type, key, status}` to disk;
   retry on failure; resume on app launch → survives app close. (Extends the singleton.)
3. **OS-level background upload** — Android WorkManager / foreground service, iOS URLSession
   background (`background_downloader`/`flutter_uploader`). Only if the ~1s upload is cut
   mid-body on flaky networks.
4. **Idempotency key** — so retries don't create duplicate vouchers.

### 5d. Env mismatch to reconcile
`parsing.env.yaml` points to a **different** Supabase/backend project
(`ztugwhevemibdrzqafyw` / `…-950406969086`) than the app's `config.dart`
(`yynuuysvjeipawzfbeme` / `…-828647628834`). Confirm which project the **live** parsing
service actually deploys against before backend work.

---

## 6. The timer pie UI (done)
`queue_loading_tile.dart` `_StepTimerPainter`: a solid wedge sweeps clockwise from 12
o'clock, filling the circle over 60s; the **whole wedge** colour steps at each 15s mark
(green `0xFF1D7A3A` → amber `0xFFF2C94C` → orange `0xFFE08A1E` → red `0xFFD94F3A`); unfilled
track is **white**; thin `AppPalette.ink` border. Advances on the row's existing 1s ticker.
(If a per-15s reset-and-refill is wanted instead of one continuous minute fill, that's a
one-line change in the painter.)

---

## 7. Constraints still in force
- Commit only the four feature files; never the secrets/config pile.
- Publishable/anon keys only in client config; never a service-role key; RLS required.
- Supabase MCP treated read-only; DB writes need explicit per-migration confirmation.
- **Do NOT run concurrent test requests against the live parse backend** (can stall the
  RunPod queue).
- Push always sets `narration='Replara AI'`; purchase vendors = Sundry Creditors, sale
  customers = Sundry Debtors.

---

## 8. One-line for the next chat
The realtime-driven count is **built, verified on device, uncommitted** (4 files); the
**backend async request–reply + `job_id` correlation + durability** is the **pending next
phase** (§5) — start there after committing the app work.
