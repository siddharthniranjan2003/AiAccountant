# AI Accountant — Manual Test Results

Companion to `aiaccountant_backend_interaction_testplan_2026-06-30.md`.
Env under test: **testing** — web app https://tallybridge-testing-env-636d4.web.app/ → Supabase **yynuu**.
Driver: Claude Code + Playwright MCP (real browser; Firebase session read from IndexedDB, network captured).

| TC | Priority | Platform | Date | Result |
|----|----------|----------|------|--------|
| AUTH-27 — Sign out clears caches and returns to Login | P0 | web | 2026-07-01 | ✅ **PASS** |
| AUTH-27 — Sign out clears caches and returns to Login | P0 | android (emulator P10) | 2026-07-01 | ✅ **PASS** |
| AUTH-33 — activate push-to-Tally authenticated by x-api-key only (no Bearer) | P0 (security) | backend (testing 828/yynuu) | 2026-07-01 | ⚠️ **CONFIRMED — weakness present** |
| SCAN-5 — Choose Sale routes to the sale parse URL and Sale badge tab | P0 | android (emulator P10) | 2026-07-01 | ✅ **PASS** |
| SCAN-6 — Choose Purchase routes to the purchase parse URL and Purchase badge tab | P0 | android (emulator P10) | 2026-07-02 | ✅ **PASS** |
| SCAN-9 — Android passes the platform gate and opens the ML Kit scanner | P0 | android (emulator P10) | 2026-07-02 | ✅ **PASS** |
| SCAN-10 — Successful scan adds a capture and fires the enqueue | P0 | android (emulator P10) | 2026-07-02 | ✅ **PASS** |
| SCAN-20 — Parse endpoint is unauthenticated (anyone with the URL) | P0 (security) | backend (parsing 828) | 2026-07-02 | ⚠️ **CONFIRMED — weakness present** |
| SCAN-1 — Capture flow shows Sale/Purchase dialog | P1 | android | 2026-07-02 | ✅ PASS (corroborated) |
| SCAN-11 — Cancel scanner produces no scan_jobs row | P1 | android | 2026-07-02 | ✅ PASS (corroborated) |
| SCAN-24 — Scan → parse → push_queue row → badge drains (end-to-end) | P0 | android | 2026-07-02 | ✅ **PASS** |
| SCAN-25 — Silent invoice drop (SALE): parse yields no voucher | P0 (data-loss) | android | 2026-07-02 | ⚠️ **CONFIRMED gap** |
| SCAN-26 — Silent invoice drop (PURCHASE): no payload produced | P0 (data-loss) | android | 2026-07-02 | ⚠️ **CONFIRMED gap** |
| SCAN-27 — Ingest down: voucher never lands (silent loss) | P0 (data-loss) | n/a (infra) | 2026-07-02 | ⚠️ documented gap (equivalence to SCAN-25/26) |
| SCAN-36 — Remote scan climbs/drains the badge on an open web session | P0 | web (realtime) | 2026-07-02 | ✅ **PASS** |
| SCAN-39 — Duplicate purchase flagged but still enqueued | P0 | android + data | 2026-07-02 | ✅ **PASS (guarded)** — flagged + dimmed + tap-blocked; no push path (bulk bar is dead code) |
| SCAN-38 — Duplicate enqueue: same invoice scanned twice → two push_queue rows | P0 (data-integrity) | android (emulator P10) | 2026-07-02 | ⚠️ **CONFIRMED gap** (no client-side dedup; not a deploy blocker) |

---

## AUTH-27 — Sign out clears caches and returns to Login · P0 · web · **PASS** (2026-07-01)

**Test number:** +91 9560952125 (Firebase test number, fixed OTP 123456 — no real SMS).

**Steps executed (browser-driven):**
1. Loaded app → confirmed Login screen; `firebaseLocalStorageDb` = 0 auth entries (clean baseline). [`auth27_evidence/auth27-01-initial.png`]
2. Entered phone, Send OTP, entered 123456, Verify. [`02`,`03`]
3. Signed in → landed in Shell/Queue (web **side-rail** desktop layout, real voucher data). [`auth27-04-signed-in.png`]

**"Before" evidence (session + caches established):**
- Firebase session present: `uid=TYLckvddRFgDBVoEZa4ALf2Xr1z1`, `phone=+919560952125`, `provider=phone`, count=**1**.
- Network confirmed sign-in warmed all three caches (the things that must clear):
  - `stock_items` paginated **14×** (offset 0→13000, ~13–14k items) — all 200.
  - `ledgers` `group_name=Sundry Debtors` (customers) + `Sundry Creditors` (vendors) — 200.
  - plus `push_queue` (queue pending/push_now/failed + history pushed) and `scan_jobs`.

**Test action:** Profile → **Sign out** (single tap, no confirm dialog).

**"After" evidence (assertions):**
| # | Expected | Observed | ✓ |
|---|----------|----------|---|
| 1 | Returns to Login, no manual navigation | Login "Welcome back" shown immediately [`auth27-05-after-signout.png`] | ✅ |
| 2 | Firebase session cleared | `firebaseLocalStorageDb` count **1 → 0** (uid entry gone) | ✅ |
| 3 | Master caches cleared | Code `.clear()`s stock/customers/vendors on `uid==null`; Shell torn down (we're on Login). In-memory Dart caches not directly inspectable; behaviorally consistent | ✅ (code-verified) |
| 4 | Web: reload (F5) stays on Login, no session restore | After reload → Login, `firebaseCount=0` [`auth27-06-after-reload.png`] | ✅ |

**Notes / minor observations (not failures):**
- `_grecaptcha` localStorage key persists after sign-out — harmless (Firebase reCAPTCHA state, not a session).
- **No confirmation dialog** on Sign out — one accidental tap logs the user out (UX nit; matches code).
- The on-disk report/image cache privacy concern (**RPT-31**) does **not** apply on web (no path_provider); it remains a mobile-only case to test separately.

**Verdict: PASS.** Sign-out flips the Firebase auth stream to null, the `main.dart` gate reactively renders Login with no manual nav, the persisted session is cleared, and a page refresh does not restore it.

---

## AUTH-27 — Sign out clears caches and returns to Login · P0 · **android (emulator P10)** · **PASS** (2026-07-01)

**Harness:** Android emulator P10 (1280×2856), `mobile-mcp` (screenshot/tap/type) + adb `run-as` on the **staging-debug** APK (staging flavor = testing Firebase project `tallybridge-testing-env-636d4`, project number 639712744833 — same project as the web test). Dart config defaults → yynuu/testing. Test number +91 9560952125 / 123456 (Firebase test number).

**Method:** user drove the app taps; Claude verified each checkpoint via adb (no root needed — debug build allows `run-as` to read the app's private data dir).

| # | Expected | Observed | ✓ |
|---|----------|----------|---|
| 1 | Signed-in session persisted | `shared_prefs/com.google.firebase.auth.api.Store.[DEFAULT]+1:639712744833:…xml` = **4397 bytes**, contains uid `TYLckvddRFgDBVoEZa4ALf2Xr1z1` (same user as web) | ✅ |
| 2 | Sign-in warmed caches | Queue rendered with live voucher data; mobile bottom-nav layout (vs web side-rail) | ✅ |
| 3 | Sign out → Login, no manual nav | "Welcome back" login shown | ✅ |
| 4 | Firebase session cleared | Store file **4397 → 67 bytes** (emptied shell), uid occurrences **0**, no `FIREBASE_USER`/`phoneNumber` keys | ✅ |
| 5 | Master caches cleared | in-memory `.clear()` on `uid==null` (code path) — no disk artifact to inspect; verified nothing sensitive persists on disk | ✅ (code + disk-inspection) |
| 6 | Cold relaunch stays on Login (session not restored) | Fresh `com.example.aiaccountant/.MainActivity` process → Login; store still 67 bytes / uid 0 | ✅ |

**On-disk cache inspection (while signed out):** `app_flutter/` has only flutter_assets; **no `reports/` or `invoice_images/` dirs** (none created this session, so nothing to leak). Note: had a Report been opened, its CSV would persist through sign-out (**RPT-31** — deliberately test with a 2nd user).

**Platform delta vs web:** mobile uses the on-screen numeric OTP keypad (web = physical keyboard) and bottom-nav (web = side-rail). Firebase session persists to `shared_prefs` (web = IndexedDB `firebaseLocalStorageDb`); both cleared identically on sign-out.

**Verdict: PASS on Android**, consistent with web. AUTH-27 confirmed on both platforms.

---

## AUTH-33 — Push-to-Tally `activate` is authenticated by x-api-key only (no Bearer JWT) · P0 security · ⚠️ **CONFIRMED** (2026-07-01)

**Target:** testing backend `https://tallybridge-backend-828647628834.asia-south1.run.app/api/sync/push-queue/activate` (GCP 828647628834 / yynuu). Method: direct API probe (`node https`), non-mutating (nonexistent job_id → no row flipped). Shipped client key from `env/testing.json` `ACTIVATE_API_KEY = sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl`.

| # | Request (no Authorization/Bearer on any) | HTTP | Proves |
|---|------------------------------------------|------|--------|
| A | valid shipped key + non-UUID job_id | 500 `invalid input syntax for type uuid` | reached DB query → past auth |
| A' | valid shipped key + well-formed nonexistent UUID | **404** `Push queue job not found` | reached "not found" path → past auth |
| D | valid shipped key + empty job_id | **400** `job_id is required` | reached handler validation → past auth |
| B | wrong key | **401** `Unauthorized` | x-api-key is the sole gate |
| C | no key | **401** `Unauthorized` | no key = denied |

**Finding (CONFIRMED):** the `activate` endpoint (which queues a real Tally voucher push) authenticates **solely** on `x-api-key`. The correct key passes auth and reaches the push logic; a wrong/absent key is 401. **No Firebase Bearer token is involved** — corroborated in code: `voucher_detail_sheet.dart` `_activate()` builds the POST with only `Content-Type` + `x-api-key` + `x-request-id` (no `Authorization`). Additionally the key is a `sb_publishable_*` string that is **shipped in every web bundle / APK** yet is *also* the backend's server-side `API_KEY` secret (compared via `timingSafeEqual`). push_queue.id is a UUID (learned from probe A).

**Impact:** anyone who extracts the shipped key (trivial) + obtains a **pending** `job_id` can `POST /activate` to flip it `pending→push_now`, queuing a real push to the tenant's Tally — with **zero user authentication**. No real row was flipped during this test.

**Exploitability CONFIRMED (2026-07-02):** `job_id`s are **enumerable with the same shipped key** — `GET /rest/v1/push_queue?status=eq.pending` via the anon/publishable key returned pending rows *with their `id`s* (HTTP 200, RLS permissive). So the full chain is real: extract key → list pending job_ids → activate. This is functionally harmless (nothing breaks) but a genuine unauthorized-push vulnerability. Also implicates push_queue RLS (anon can read pending rows — cf. HIST-51/PUSH-82 tenant-scoping).

**Recommended fix (triage):** require a Firebase Bearer JWT on `activate` (as user-initiated actions warrant) and/or move the service secret off the client (separate the shipped publishable key from the server `API_KEY`); scope push_queue rows to the authenticated tenant so a `job_id` cannot be activated cross-tenant.

**Verdict: CONFIRMED P0 security weakness** — behavior is exactly as the test predicted; the endpoint is key-only auth.

---

## SCAN-5 — Choose Sale routes to the sale parse URL and Sale badge tab · P0 · **android (emulator P10)** · **PASS** (2026-07-01)

**Emulator scan setup:** AVD is a Google Play image (`sdk_gphone16k_x86_64`, GMS + Play Store present) so ML Kit DocumentScanner runs. Instead of the live camera, used **gallery import** (app sets `isGalleryImport: true`): `adb push parsing/challan_image.jpg → /sdcard/Pictures/scan5_sale_invoice.jpg`, indexed in MediaStore. (Path-conv gotcha: use `MSYS_NO_PATHCONV=1` so Git Bash doesn't mangle `/sdcard/...`.)

**Method:** user drove taps (sign in → Camera → **Sale** → scanner → import invoice → Save); Claude verified via the yynuu `scan_jobs` table (anon-key REST) + emulator screenshot.

| # | Expected | Observed | ✓ |
|---|----------|----------|---|
| 1 | Choosing Sale inserts a `scan_jobs` row `type='sale'` (its id = the parse `job_id`) | New row `type=sale`, id `6bbf5841-eb2d-402e-8727-8507c49200b3`, `2026-07-01T13:00:20Z` (baseline rows were all 2026-06-25) | ✅ |
| 2 | Parse routed to `saleParseUrl` (`/?type=sale&push=queue`) + `&job_id=` | `type='sale'` deterministically selects `saleParseUrl` in `app_shell.dart._enqueueScan`; row id is the appended job_id | ✅ (code + scan_jobs) |
| 3 | Sale **badge tab** shows Processing + timer | Screenshot: Sale tab "Processing… 1" with ring | ✅ |

**Note:** direct HTTPS interception of the outbound parse POST isn't feasible from the emulator, so the sale URL is verified via the `scan_jobs.type='sale'` proxy + code path (both deterministic), plus the badge. End-to-end drain (scan_jobs DELETE + sale voucher lands in Sale queue) = SCAN-24, follow-on.

**Verdict: PASS** — Sale selection routed to the sale parser with the job_id and lit the Sale badge.

---

## SCAN-6 — Choose Purchase routes to the purchase parse URL and Purchase badge tab · P0 · **android (emulator P10)** · **PASS** (2026-07-02)

**Setup:** `adb push` EMKAY TOOLS purchase invoice → `/sdcard/Pictures/scan6_purchase_invoice.png` (indexed in MediaStore); gallery import in the ML Kit scanner. Same you-tap / Claude-verify split.

| # | Expected | Observed | ✓ |
|---|----------|----------|---|
| 1 | Choosing Purchase inserts `scan_jobs` row `type='purchase'` (id = parse job_id) | New row `type=purchase`, id `2fd9065d-3175-4841-9060-58cc5da245b6`, `2026-07-02T05:52:35Z` (newest; baseline all 2026-06-25) | ✅ |
| 2 | Parse routed to `purchaseParseUrl` (`/docstrange?purchase=all&source=runpod`) + `&job_id=` | `type='purchase'` deterministically selects `purchaseParseUrl` in `_enqueueScan`; row id = job_id | ✅ (code + scan_jobs) |
| 3 | Purchase **badge tab** shows Processing + timer | Screenshot: Purchase tab "Processing… 1" with ring | ✅ |

**Bonus observation:** the invoice scanned is EMKAY TOOLS ₹3,99,653; the Purchase queue already contains "EMKAY TOOLS LIMITED · ₹3,99,653 · **Duplicate: Already Exists In Queue**" — so this scan is expected to be flagged a duplicate on landing (feeds SCAN-39 / QUEUE-29 duplicate-purchase detection). Sale/purchase scanning both confirmed working on emulator via gallery import.

**Verdict: PASS** — Purchase selection routed to the purchase parser with the job_id and lit the Purchase badge.

---

## SCAN-9 — Android passes the platform gate and opens the ML Kit scanner · P0 · android · **PASS** (2026-07-02)

Claude-driven (Camera → capture dialog → choose type → scanner). Tap Camera → **"What is this?"** dialog (Sale / Purchase, "Then camera opens, already tagged") = **SCAN-1** ✅. Choosing Purchase launched the **Google ML Kit DocumentScanner** — full GMS UI confirmed via a11y ids `com.google.android.gms.optional_mlkit_docscan_ui:id/*` (page_photoview, Enhance/Filters/Crop & rotate/Clean, page thumbnails carousel, add_page, Discard scan / Next). It auto-captured the emulator's **virtual-scene camera** (checkerboard test pattern) — i.e. the live camera shows the default emulator scene, not an invoice (why we use gallery-import for SCAN-5/6). **Android platform gate passed → scanner opened.** ✅

**Corroborated for free:**
- **SCAN-1** (P1): capture-type dialog shown. ✅
- **SCAN-11** (P1): tapped **Discard scan** → `scan_jobs` newest rows unchanged (back to 2026-06-25 baseline) → **no scan_job created on cancel**, no stuck badge. ✅
- **SCAN-24** (P0): earlier SCAN-5 sale scan parsed end-to-end and landed as "SHREE SHYAM ENTERPRISES ₹16,844.36" in the Sale queue; its scan_job was deleted (badge drained). ✅
- **SCAN-39** (P0): the SCAN-6 EMKAY ₹3,99,653 purchase parsed and landed **flagged "Duplicate: Already Exists In Queue"** — duplicate correctly detected. ⚠️ Note: it is still **enqueued as a row** (flag is visual); the "can still be pushed anyway" aspect of SCAN-39 remains untested.

**Verdict: PASS.** (web/iOS complement — scanner hidden/blocked — remains to test per XCUT-55; on web the Camera nav item is absent, observed during AUTH-27.)

---

## SCAN-10 — Successful scan adds a capture and fires the enqueue · P0 · android · **PASS** (2026-07-02)

You-tap / Claude-verify. Completed a Sale scan (gallery import → Save).

| # | Expected | Observed | ✓ |
|---|----------|----------|---|
| 1 | "Your Sale voucher is being processed…" snackbar (2s) | User confirmed seeing it | ✅ |
| 2 | `scan_jobs` row inserted | New row `type='sale'`, id `58a24905-b451-4769-8f0c-b74a541e0e9e`, `2026-07-02T06:14:30Z` (matches app 11:44 IST) | ✅ |
| 3 | Parse POST dispatched | Sale queue shows "Processing… 1" (badge climbed off the scan_jobs insert) | ✅ |
| 4 | CapturedShot added to tray | Not directly observed; in `app_shell` the `_captures.add(CapturedShot)` + `_enqueueScan` are the same success block — snackbar+badge prove it ran | ✅ (code-verified) |

**Verdict: PASS** — a completed scan added the capture and fired the full enqueue (snackbar + scan_jobs insert + parse dispatch).

---

## SCAN-20 — Parse endpoint is unauthenticated · P0 security · ⚠️ **CONFIRMED** (2026-07-02)

**Target:** parsing service `https://tallybridge-parsing-828647628834.asia-south1.run.app` (testing). Direct `node https` probe, no auth headers, no valid PDF (non-mutating).

| Request (no api key / Bearer) | HTTP | Meaning |
|---|---|---|
| GET `/?type=sale&push=queue` | 404 `{"ok":false,"error":"Not found"}` | reached routing, not 401 → no auth gate |
| GET `/docstrange?purchase=all&source=runpod` | 404 | same |
| POST `/?type=sale&push=queue`, junk body | **500** `Unable to get page count… May not be a PDF` | **accepted the unauthenticated POST and tried to parse it** — failed only on invalid bytes |

**Finding (CONFIRMED):** the parse service has **no authentication** — the app's `sendScanToParser` sends only `Content-Type: application/pdf` (no key/Bearer), and the deployed service matches. Anyone with the URL can POST a document; it is parsed and a `push_queue` voucher is created. The only auth boundary is parsing-service→main-backend, **not** app→parsing-service.

**Combined attack chain (SCAN-20 + AUTH-33):** unauthenticated POST to parse URL → `push_queue` voucher created → activate with the shipped key (AUTH-33) → **voucher pushed into the tenant's TallyPrime**. Full unauthorized-write path using only public URLs + the bundled key. No voucher was created in this test (junk body).

**Recommended fix:** put the parse endpoints behind auth (API key/JWT or an authenticated app→parser boundary), rate-limit, and validate the caller — together with the AUTH-33 fixes.

**Verdict: CONFIRMED P0 security weakness.**

---

## SCAN-24 — Scan → parse → push_queue row → badge drains (end-to-end) · P0 · android · **PASS** (2026-07-02)

Verified via backend timing trace of the SCAN-10 sale scan (no extra taps needed):

| Stage | Evidence |
|---|---|
| Scan enqueued | `scan_jobs` sale row `58a24905-b451-4769-8f0c-b74a541e0e9e` @ **2026-07-02T06:14:30Z** |
| Parse → voucher | `push_queue` **SHREE SHYAM ENTERPRISES · GST SALE · pending @ 06:17:01Z** (~2.5 min round-trip) |
| scan_job deleted → badge drains | job `58a24905` **absent** from scan_jobs afterwards (only 2026-06-25 orphans remain) |

Corroborating: SCAN-6 EMKAY purchase also landed (`EMKAY TOOLS LIMITED · Purchase · pending @ 05:54:59Z`). Single-client badge drain confirmed; "on every client" is via the `scan_jobs_live` realtime DELETE echo (multi-client-simultaneous = SCAN-36, not yet tested).

**Verdict: PASS** — the happy-path capture→parse→queue→drain cycle works end-to-end.

---

## SCAN-25 / SCAN-26 — Silent invoice drop when parse yields no voucher · P0 (data-loss) · android · ⚠️ **CONFIRMED gap** (2026-07-02)

**What:** when a scan produces no voucher (unreadable image, unknown party/vendor, OCR miss, parsing/RunPod down), the invoice is **silently lost** — no `push_queue` row, `scan_jobs` row never deleted (orphaned), "Processing…" badge drains at the 300s client TTL, and **no error toast/dialog/record**. User thinks it's processing, then nothing.

**Method:** scanned a garbage image (emulator checkerboard) once as Sale, once as Purchase; backend-polled ~5 min each.

| Path | scan_jobs id @ time | Voucher produced (5-min poll) | scan_job deleted? |
|---|---|---|---|
| SALE (SCAN-25) | `c1b5adf6…` @ 06:31:54Z | **0 — none** | No (orphaned; still present at 07:08+) |
| PURCHASE (SCAN-26) | `3bdb2e5b…` @ 07:08:40Z | **0 — none** | No (orphaned) |

Contrast (happy path): real scans land a voucher in ~2.5 min. So the 5-min no-show = dropped.

**Consequence of scan_job not being deleted:** harmless in itself — badge clears via the 300s client sweep (`ScanJobsService._maxAge`), and orphan rows are ignored by the time-windowed `_refresh` query (they just accumulate as DB cruft). The real harm is the **silent data loss**: a scanned money document vanishes with no user signal (missed bookkeeping entry). The orphaned scan_job (>5 min old, never deleted) is actually a usable **failure signal** for a fix.

**Recommended fix:** surface a failure notice / failed-scan record instead of a silent 300s drain (e.g., detect a scan_job still present past the parse window and notify the user / mark it failed).

**Client-side observation (user):** badge silently vanished at ~5 min, no error dialog — [confirm].

**Verdict: CONFIRMED P0 data-loss gap on both sale and purchase scan paths.**

---

## SCAN-27 — Backend push-queue ingest down: voucher never lands · P0 (data-loss) · ⚠️ **DOCUMENTED GAP** (2026-07-02)

Not live-reproduced — requires disabling the parser's push_queue ingest (parser→Supabase/backend), an infra action not safely doable against the testing stack. **Confirmed by equivalence:** the user-facing outcome is identical to SCAN-25/26 — parser can't create a `push_queue` row → `scan_jobs` orphaned → badge sweeps at 300s → no voucher, no error. Same silent-loss family, same fix. Difference is only the cause (ingest infra down vs parse-no-match); the app can't distinguish them. Same recommended fix (surface a failure / failed-scan record). A true repro would need someone to point the parser at a bad Supabase URL / block its insert.

---

## SCAN-36 — Remote scan climbs (and drains) the badge on an open web session · P0 · web · **PASS** (2026-07-02)

Cross-client realtime test. Web app open + signed in (Queue → Sale, clean baseline); Claude inserted/deleted `scan_jobs` rows via anon REST (the exact DB ops a phone scan / the parsing service perform), user observed the web only.

| Step | Action (backend) | Web observed | ✓ |
|---|---|---|---|
| Climb | INSERT scan_jobs sale row `40a8fd88…` @07:34:55Z | Web Sale tab showed **"Processing… 1"** + ring within ~1–2s, untouched | ✅ |
| Drain | DELETE that row (204) | Web badge **disappeared** (back to 0), untouched | ✅ |

Proves the `scan_jobs_live` INSERT/DELETE realtime echo propagates the "Processing…" badge to a client that did **not** originate the scan. Anon `scan_jobs` insert/delete confirmed working (201/204). Also closes the "drains on every client" piece left open in SCAN-24.

**Verdict: PASS** — cross-client badge climb + drain via realtime works.

---

## SCAN-38 — Duplicate enqueue: same invoice scanned twice → two push_queue rows · P0 (data-integrity) · android · **CONFIRMED gap** (2026-07-02)

**Env:** testing — yynuu (`yynuuysvjeipawzfbeme`), emulator P10. User-driven scans; Claude verified from Supabase anon REST.

**Root cause (code-grounded):** there is **no client-side de-duplication** anywhere in the scan path.
- `app_shell.dart` `_openTaggedCameraFlow` → each completed scan adds its own `CapturedShot` (id = `microsecondsSinceEpoch_path`) and calls `_enqueueScan` with `unawaited(...)`. No `_busy`/in-flight guard on the camera nav (`_onNavSelected(2)`), no PDF-hash or invoice-number check.
- `scan_jobs_service.dart` `startScan` just INSERTs a `scan_jobs` row and returns its id — no dedup key.
- Parser inserts one `push_queue` row per parse request. Sales have **no** duplicate gate; purchases only *flag* `invoice_exists` (SCAN-39) but still enqueue.

**Steps executed (live):** scanned the same BALAJI H/W AGENCIES handwritten sale invoice **twice** (two full scanner sessions), Sale type, then waited.

**Evidence (Supabase, delta from a fixed START timestamp):**
| # | Expected | Observed | ✓ |
|---|----------|----------|---|
| 1 | Two independent scan_jobs rows | `new scan_jobs=2 (sale,sale)` immediately after both scans | ✅ |
| 2 | Two push_queue voucher rows for the SAME invoice | At t+150s, 2 `pending` rows, both party **BALAJI H/W AGENCIES**, 3s apart: `c6e17051-64a7-4c22-9471-883831f16f4e` (08:23:57Z) + `204cb0d5-9a4c-465c-b4c4-08bc8217468a` (08:24:00Z) | ✅ |
| 3 | Badge drains correctly (parser deletes scan_jobs) | Both scan_jobs DELETEd after parse; fresh scan_jobs count back to 0 | ✅ |
| 4 | No dedup / no block / no warning | Both rows enqueued with no de-dup, no duplicate warning on the sale path | ✅ (defect) |

**Impact:** double-posting hazard — the same invoice can be pushed to Tally twice. Sales entirely ungated; purchases rely on the user noticing the `invoice_exists` flag before push.

**Deploy call:** **NOT a deploy blocker** (single-client). No automatic double-fire exists in the normal flow — a duplicate requires a deliberate/accidental re-scan. Proper fix = content/invoice-number de-dup (parser-side), post-deploy alongside finding #1 (OCR concat) and #2 (silent drop).

**Test-data note:** the two duplicate BALAJI rows (`c6e17051…`, `204cb0d5…`) were created on the yynuu **test** project by this test.

**Verdict: CONFIRMED data-integrity gap (no client-side dedup).**

---

## SCAN-39 — Duplicate purchase: invoice_exists flagged but voucher still enqueued · P0 (data-integrity) · android + data · **PASS (guarded)** (2026-07-02)

**Env:** testing — yynuu. Verified from Supabase (existing EMKAY row) + code (`queue_row_tile.dart`, `queue_screen.dart`, `queue_bulk_bar.dart`, `push_queue_service.dart`, `models.dart`).

**Data evidence:** purchase row `36e11778-a470-4f14-8f74-59637c29373e` (EMKAY TOOLS LIMITED) has `voucher_payload.invoice_exists = true` and `status = pending` — flagged as already-in-Tally **and** still sitting in the queue (not auto-removed). All sale rows (SHREE SHYAM, and the two duplicate BALAJI sale rows from SCAN-38) have `invoice_exists = false` — confirming **dedup is purchase-only; sales are never flagged.**

**How the app surfaces / gates it (three distinct signals):**
1. `invoice_exists` (backend = "already in TallyPrime") → `QueueEntry.invoiceExists` (scanResult spreads voucher_payload). Row is **dimmed (opacity 0.56)** and shows a red **"Duplicate"** label (`queue_row_tile.dart:32,105`).
2. **Tap is blocked:** `queue_screen.dart:191` — opening an `invoiceExists` row shows snackbar *"This Invoice Is Already In TallyPrime"* and does **not** open the detail sheet → the duplicate cannot be pushed individually.
3. `isQueueDuplicate` (client-computed, purchase-only): same invoice `reference` on an older queue row → red **"Duplicate: Already Exists In Queue"** label + dimmed. Sale rows never flagged.
4. `duplicacy` field on scan-result resolution → `_DuplicatePurchaseDialog` popup (`voucher_detail_sheet.dart:316`). (Not present on the EMKAY row; separate path.)

**No bulk-push bypass:** `QueueBulkBar` is **defined but wired nowhere** (dead code). Push is exclusively per-voucher via the tap-blocked detail sheet.

**Verdict: PASS (guarded).** The plan's "relies on the user noticing" is understated — duplicate purchases are flagged, dimmed, and their push path is actively blocked. Residual risks (not new defects): (a) **sales have no dedup at all** — captured by SCAN-38; (b) **false-positive `invoice_exists`** would hard-block a legitimate purchase with no in-app override (tap refused, no edit) — watch item.
