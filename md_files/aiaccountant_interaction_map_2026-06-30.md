# AI Accountant — Definitive Interaction Map (Mobile + Web)

> Scope: the single Flutter codebase at `D:/Desktop/Ai_Accountant/aiaccountant/lib` (Android mobile **and** Web) and every external system it touches. Backend code referenced from `D:/Desktop/TallyBridge/backend/src`. Grounded in source as of 2026-06-30.

---

## 1. System context

The app is a **thin capture-and-review client**. It talks to four external systems, two of them directly and two through the cloud.

| # | External system | App reaches it… | Transport / auth | What it's for |
|---|-----------------|-----------------|-------------------|----------------|
| 1 | **Firebase Auth** | **Directly** | Phone OTP; `getIdToken()` JWT | Login; the JWT becomes the `Authorization: Bearer` for backend calls |
| 2 | **Supabase (client project)** | **Directly** (anon/publishable key, RLS) | `supabase_flutter` REST + Realtime websocket | Read/write `push_queue`, `scan_jobs`; read `ledgers`, `stock_items`, `voucher_items`; 4 realtime channels |
| 3 | **Main backend** — Cloud Run `tallybridge-backend` | **Via backend** (`ApiClient` / `activateUrl`) | HTTPS + `x-api-key` (+ optional Bearer) | Push-to-Tally activation, stored invoice images, reorder-levels CSV |
| 4 | **Parsing service** — Cloud Run `tallybridge-parsing` | **Directly** (raw PDF POST, fire-and-forget) | HTTPS, `Content-Type: application/pdf` | OCR/VLM parse → it **inserts** a `push_queue` row and **deletes** the `scan_jobs` row |

```
                 ┌────────────────────────────── Firebase Auth (OTP, JWT)
                 │
   ┌─────────────┴─────────────┐
   │   AI Accountant (Flutter)  │──── raw PDF ───▶ Parsing service ──┐ inserts push_queue
   │   Android mobile + Web     │                                    │ deletes scan_jobs
   └──────┬──────────────┬──────┘                                    ▼
          │ direct REST   │ ApiClient (x-api-key + Bearer)      ┌───────────┐
          │ + Realtime    └──────────────────▶ Main backend ───▶│ Supabase  │
          ▼                                    (Cloud Run)       │  client   │
      Supabase client project ◀──────────────────────────────── │  project  │
      (push_queue, scan_jobs, ledgers, stock_items, voucher_items)└───────────┘
```

Tally itself is **never** contacted by the app. Push-to-Tally is asynchronous: the app flips a queue row to `push_now` via the backend, and the desktop TallyBridge engine (separate process) does the actual XML push and writes the result back to `push_queue`, which the app observes over Realtime.

Environment note: default build = **testing** (`yynuu` Supabase). Production = `ztugw`. The reorder-levels endpoint reads a **separate** client Supabase on the backend (`SUPABASE_URL_Client`), distinct from the project the app connects to.

---

## 2. Backend endpoints the app calls

All `ApiClient` calls send headers: `Content-Type: application/json` (dropped for raw/bytes GETs), `x-api-key: Config.mrpApiKey`, `x-request-id: <corr id>`, and `Authorization: Bearer <Firebase JWT>` when a user is signed in. A non-2xx is reported to Sentry with the request id; `401` throws `Unauthorized`.

### Reports surface (`report_screen.dart` via `ApiClient.getRaw`)

| Method | Path | Auth (backend) | Purpose | Error codes |
|--------|------|----------------|---------|-------------|
| GET | `/api/sync/reorder-levels/{reportKey}?company_name=K V ENTERPRISES&format=csv` | `requireClientApiKey` — `x-api-key` timing-safe vs **`API_KEY_CLIENT`**; reads **client** Supabase (`SUPABASE_URL_Client`) | Inventory reorder report as CSV | `400` invalid report key, `409` company lookup (duplicate/missing company), `500` |

> Contract gotcha: the app sends `Config.mrpApiKey` as `x-api-key`. For this endpoint to authorize, `mrpApiKey` must equal the backend's `API_KEY_CLIENT`. `company_name` is **hardcoded** to `K V ENTERPRISES`.

### Voucher detail / image surface

| Method | Path | Auth (backend) | Purpose | Error codes |
|--------|------|----------------|---------|-------------|
| GET | `/api/sync/push-queue/{rowId}/image/{page}` | `requireApiKey` (`x-api-key` **or** Firebase Bearer) | Streams stored scanned-invoice JPEG (page `0..N-1`, N from `source_payload.scan.pages`) | `404` storage not configured / image not found, `400` bad id or page, `500` read failed |
| POST | `/api/sync/push-queue/activate`  body `{ job_id }` | `requireApiKey` | Flips the queue row `pending → push_now` and clears `error_message`; queues the desktop push | `400` no `job_id`, `404` job not found, `409` wrong company / **not `pending`** (msg includes current status) / could-not-activate, `500` |

> Auth-contract nuance: the **activate** call in `voucher_detail_sheet.dart` bypasses `ApiClient._headers` and posts via `ApiClient.client` with only `Content-Type`, `x-api-key: Config.activateApiKey`, and `x-request-id` — **no Firebase Bearer**. Push-to-Tally is therefore authorized purely by the shipped API key. The activate URL is configured separately (`Config.activateUrl`) but currently points at the same Cloud Run service.

---

## 3. Direct Supabase operations & realtime channels

### Table / RPC operations (anon key, RLS)

| Table | Op | Where | Filter / shape | Purpose |
|-------|-----|-------|----------------|---------|
| `push_queue` | SELECT | `PushQueueService.refresh` | `status in (pending, push_now, failed)`, `order created_at desc`; cols `id,status,created_at,voucher_payload,source_payload,edit_state,pushed_at,error_message` | Load the live queue |
| `push_queue` | SELECT | `HistoryScreen` | `status = pushed`, `order pushed_at desc` | History list |
| `push_queue` | SELECT (single) | `HistoryScreen._ingestPushedRow` | `eq id` | Re-fetch full row when Realtime UPDATE omitted TOASTed `voucher_payload` |
| `push_queue` | UPDATE | `_persistEditsToSupabase` | `{voucher_payload}` `eq id` **`eq status pending`**, `.select('id')` to confirm | Save voucher edits (only while pending) |
| `push_queue` | UPDATE | `_activate` (pre-push) | `{voucher_payload}` `eq id` (**no status guard**) — overwrites narration to `Replara AI` | Persist narration before activate |
| `push_queue` | DELETE | `_confirmAndDiscard` | `eq id` | Discard a queued voucher |
| `scan_jobs` | INSERT | `ScanJobsService.startScan` | `{type}` `.select(id,type,created_at).single()` | Record an in-flight scan (badge +1); returns `job_id` |
| `scan_jobs` | SELECT | `ScanJobsService._refresh` | `gte created_at (now-300s)` | Catch-up / resync badge state |
| `ledgers` | SELECT | `CustomersCache` | `eq group_name 'Sundry Debtors'`; cols `name,group_name,state` | Customer picker (sale party) |
| `ledgers` | SELECT | `VendorsCache` | `eq group_name 'Sundry Creditors'` | Vendor picker (purchase party) |
| `stock_items` | SELECT | `StockItemsCache.fetch` | cols `name,group_name,rate,unit,part_code`, `order name`, `.range()` paginated **1000/page** (~13k rows) | Stock catalog (PURCHASE picker; unit/part-code lookups) |
| `voucher_items` | SELECT | SALE stock picker | party-aware history (per-party item rows; no `part_code`) | Stock picker for SALE lines |

> Parsing service writes (server-side, not the app): **INSERT** `push_queue` invoice row + **DELETE** `scan_jobs` row when an invoice lands.

### Realtime channels

| Channel | Table / events | Filter | Consumer & effect |
|---------|----------------|--------|-------------------|
| `push_queue_live` | `push_queue` INSERT / UPDATE / DELETE | active-status only on insert | Live queue list; row leaves only on `status=pushed`; UPDATE keeps prior `edit_state` if the echo omits the column |
| `scan_jobs_live` | `scan_jobs` INSERT / DELETE | — | "Processing…" badge +1 / −1 on **every** client; 300 s sweep + foreground `resync` guard stuck badges |
| `history_push_queue` | `push_queue` INSERT / UPDATE / DELETE | — | History list (`status=pushed`); re-fetches full row when payload omitted |
| `vd_status_<rowId>` | `push_queue` UPDATE | `eq id = rowId` | Per-voucher push status while the detail sheet is open; drives the pushing→result transition |

---

## 4. Critical end-to-end sequences

### (a) Login / OTP
1. `LoginScreen`: user enters 10-digit number; app prefixes **`+91`** and calls `FirebaseAuth.verifyPhoneNumber` (with `forceResendingToken` on resend).
2. `codeSent` → navigate to `OtpScreen` with `verificationId` (Android may auto-verify via `verificationCompleted`).
3. `OtpScreen`: 6 digits (on-screen keypad on narrow screens; physical keyboard + Ctrl/⌘-V paste on desktop) → `PhoneAuthProvider.credential` → `signInWithCredential`.
4. `main.dart` `StreamBuilder(authStateChanges)` flips Splash → `AccountantShell`. On web refresh the persisted session restores via the same stream.
5. `_wireSessionAndSentryUser` (uid-guarded): on sign-in, eagerly `fetch()` `StockItemsCache` + `CustomersCache` + `VendorsCache` and tag the Sentry user; on sign-out, `clear()` all three.
6. Subsequent backend calls attach `Authorization: Bearer <getIdToken()>`.

### (b) Scan → Parse → Queue  *(scan step is Android-only)*
1. `AppShell`: user picks Sale/Purchase (`CaptureTypeDialog`). On web/iOS a snackbar says scanning is Android-only and the flow stops.
2. ML Kit `DocumentScanner` (jpeg+pdf, up to 20 pages, gallery import) returns a PDF path; a local `CapturedShot` is added.
3. `_enqueueScan`: shows "being processed…" snackbar, then `ScanJobsService.startScan(type)` **inserts a `scan_jobs` row** → `scan_jobs_live` INSERT makes the badge climb on every client; returns the row id as **`job_id`**.
4. `sendScanToParser(pdfPath, url)` POSTs the raw PDF (fire-and-forget, 300 s timeout) to:
   - Sale: `…/?type=sale&push=queue&job_id=<id>`
   - Purchase: `…/docstrange?purchase=all&source=runpod&job_id=<id>`
5. Parsing service parses, **inserts a `push_queue` row** and **deletes the `scan_jobs` row** (`job_id`).
6. App effects: `push_queue_live` INSERT adds the new active row to the queue; `scan_jobs_live` DELETE drains the badge everywhere. If the parse never lands, the 300 s `_maxAge` sweep expires the badge (no queue row appears).

### (c) Edit → Push-to-Tally → result
1. Queue row → `VoucherDetailSheet`. **Edit** is allowed only while `status='pending'` and after the stock cache finishes loading.
2. Edits mutate editable copies; charges rescale client-side (`inventory_ledger` gets new taxable, tax ledgers scaled by captured `_taxRatios`, discount/total recomputed). **Save** writes `voucher_payload` back via `push_queue` UPDATE guarded `eq status pending` (empty result ⇒ "may already be queued"). A vendor change also renames the party ledger line in `ledger_entries`.
3. **Push To Tally** (`_confirmAndActivate`): if still editing, prompts to Save first. **Guard:** if the party name changed but **not** all items changed, push is blocked ("Party Name is Changed!! Change all the items") — prevents posting items against the wrong ledger.
4. `_activate`: overwrites `narration='Replara AI'`, UPDATEs `voucher_payload` on the row (`eq id`), then POSTs `/api/sync/push-queue/activate {job_id: rowId}` with `x-api-key`+`x-request-id`.
5. Backend flips `pending → push_now`, clears `error_message`, returns `{success, job}`. App enters `_awaitingPushResult` (spinner; sheet stays open).
6. Desktop TallyBridge pushes to TallyPrime and writes the outcome to `push_queue`. The `vd_status_<rowId>` UPDATE delivers it: success = `status=pushed` or `tally_response.created ≥ 1`; failure = `status=failed` or `created=0 && errors ≥ 1` (with `error_message`).
7. On terminal: `onPushed` re-fetches the queue (pushed rows drop to History, failed rows stay), the sheet closes, and **sale** vouchers show a success/fail dialog. A race where the terminal update arrived before the POST returned is handled by an immediate resolve.

### (d) Report fetch (Reorder-levels)
1. `ReportScreen` → tap a category with a `reportId`.
2. Web: always `ApiClient.getRaw('/api/sync/reorder-levels/<reportId>', {company_name:'K V ENTERPRISES', format:'csv'})` (no disk cache). Mobile: serve `<reportId>.csv` from app-documents cache if present, else fetch and write it.
3. Backend `requireClientApiKey` (vs `API_KEY_CLIENT`) reads the **client** Supabase and returns CSV; `400` bad key, `409` company lookup.
4. CSV parsed → `AppSpreadsheetSheet` (sum column = `closing_stock_amount`). Share is available on mobile only (relies on the disk file; `null` on web).

---

## 5. Mobile vs Web differences

| Aspect | Android (mobile) | Web |
|--------|------------------|-----|
| Document scanning | ML Kit `DocumentScanner` (the only scan path) | Disabled — snackbar "only available on Android" |
| Text scaling | Native | Global `TextScaler(1.4)`; sheet numeric columns widened ×1.4 |
| Report CSV cache | On-disk (`getApplicationDocumentsDirectory`) | No `path_provider` → always fetch, no disk cache |
| Invoice image cache | On-disk `InvoiceImageStore` keyed by row id | No on-disk cache (images fetched from backend) |
| File share (CSV) | `share_plus` via cached file | `onShare = null` (no file to share) |
| Navigation / layout | Bottom nav; single-pane sheet with Image/Summary tabs | ≥900 px → side rail + **two-pane** image+summary; sheet width ~90% |
| OTP entry | On-screen numeric keypad | Physical keyboard typing, Enter to verify, Ctrl/⌘-V paste |
| Session restore | Cold start with persisted session | Restored on refresh via `authStateChanges` StreamBuilder |
| Badge realtime | Climbs on own scan + every other client | Climbs/drains on others' scans; no scanning of its own |

---

## 6. Data-integrity & money-path hazards

- **Hardcoded report company.** Reorder-levels always sends `company_name='K V ENTERPRISES'`. Duplicate company rows in the client project (`ztugw`) surface as **`409` "Failed to load report"** (known incident).
- **Unguarded narration overwrite.** `_activate` UPDATEs `voucher_payload` with `eq id` only (no `status='pending'` guard, unlike Save). If another client/desktop already moved the row off `pending`, this can overwrite the payload underneath it just before the backend's pending check fails.
- **Realtime column omission (TOAST / cache lag).** UPDATE echoes can drop the large `voucher_payload` (History re-fetches the full row, else shows "Unknown") and can drop the freshly-added `edit_state` (queue keeps the prior value). Both are mitigated in code but depend on those guards staying correct.
- **Push result depends on Realtime.** The sheet stays in a "pushing…" state until `vd_status_<rowId>` delivers a terminal row. A dropped socket leaves the spinner up; `onPushed`'s queue re-fetch is the recovery path. Success/fail dialog is **sale-only**.
- **Client-side money math.** Queue/History amount = `abs(first ledger_entry.amount)`; charges total = `abs(party-entry amount)`. Edits recompute taxable, scale tax ledgers **proportionally** (`_taxRatios`), and re-derive discount/total in the client before the payload is pushed — rounding and proportional scaling happen app-side, not in Tally.
- **Party/items consistency guard.** Changing only the party (not the items) blocks the push; on save the party ledger line is renamed to match — a mismatch here would post a voucher against the wrong vendor ledger.
- **Edit window race.** Edits are accepted only while `status='pending'`; the Save UPDATE returns rows to confirm, and an empty result yields "may already be queued for push." A row claimed by the desktop between Save and Push is intentionally left untouched.
- **Badge is table-derived, not counted.** `+1` on `scan_jobs` INSERT, `−1` on the parser's DELETE; a missed DELETE is swept after 300 s. A scan whose parse silently fails leaves **no** queue row — the only signal was the badge, which auto-expires.
- **Shipped API keys.** A publishable-looking `x-api-key` is compiled into the client bundle and is the **sole** auth for the activate (push-to-Tally) call; `mrpApiKey` must double as `API_KEY_CLIENT` for reports. Security rests on RLS (Supabase) and these keys, not on the Firebase JWT for those paths.