# Session Handout — AI Accountant Manual Testing (2026-07-02)

**Context:** deploy-today push. Manual testing of the AI Accountant app (Flutter, Android emulator + web) against the **testing** env. Companion to the 494-case plan (`aiaccountant_backend_interaction_testplan_2026-06-30.md`). Live results in `aiaccountant_tc_results.md`.

---

## 1. Environment & test harness (reuse next session)

| Thing | Value |
|---|---|
| Web app (testing) | https://tallybridge-testing-env-636d4.web.app/ → Supabase **yynuu** |
| Android build | **staging** flavor = testing Firebase project `tallybridge-testing-env-636d4` (proj# 639712744833). APK: `build/app/outputs/apk/staging/debug/app-staging-debug.apk`. Build: `flutter build apk --flavor staging --dart-define-from-file=env/testing.json` (gradle forbids "test…" names → testing env = `staging` flavor) |
| Emulator | AVD **P10** (`adb -s emulator-5554`); Google Play image (GMS present → ML Kit scanner works). Boot: `emulator -avd P10` |
| App package | `com.example.aiaccountant` (debug → `adb shell run-as` reads private data with NO root) |
| Login | Firebase **test number +91 9560952125 / OTP 123456** (fixed, no real SMS) |
| Backend (testing) | `tallybridge-backend-828647628834.asia-south1.run.app` (GCP 828). ⚠️ deployment flavor=ztugw CLIENT PROD — don't touch |
| Desktop | TallyBridge v1.2.16 + TallyPrime **K V ENTERPRISES** running against testing (CONNECTED). Push works when a row is `push_now` |
| MCP servers | `playwright` (web) + `mobile` (`@mobilenext/mobile-mcp`, ANDROID_HOME set) — in `~/.claude.json` local scope; **restart Claude Code to load in a fresh session** |

**Fast verification levers (no MCP needed):**
- Supabase anon REST (yynuu): key `sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl` — read/insert/delete `scan_jobs`, read `push_queue`. Use `node https`.
- Firebase session (android): `adb shell run-as com.example.aiaccountant cat shared_prefs/com.google.firebase.auth.api.Store.*.xml`.
- Firebase session (web): browser IndexedDB `firebaseLocalStorageDb` via Playwright `browser_evaluate`.
- **mobile-mcp coords are DEVICE pixels** (from `mobile_list_elements_on_screen`), NOT the scaled screenshot. Flutter web: click `flt-semantics-placeholder` to enable the a11y tree.
- Gallery test images already pushed to emulator `/sdcard/Pictures/`: `scan5_sale_invoice.jpg` (SHREE SHYAM sale), `scan6_purchase_invoice.png` (EMKAY purchase), `scan_balaji_sale.jpeg` (handwritten Balaji sale). Use `MSYS_NO_PATHCONV=1` when `adb push` to `/sdcard/...` in Git Bash.

---

## 2. Working agreement (user preferences — follow these)

- **Single-client deploy → SECURITY findings are LOW priority** (log, don't push). **FLOW-breaking / data-loss / data-integrity = HIGH priority.**
- **Minimize MCP driving** (it's slow). Default: give the user **sequential manual steps (they tap)**; Claude **verifies from backend/adb/API/logcat**. Use MCP only when necessary (e.g. observing a UI badge).
- **Recommend decisively; don't present option menus.**
- **Log results to the Google Sheet** `AI Accountant App Issues` tab: https://docs.google.com/spreadsheets/d/1l0yn7kG_tWctfc2G6YWB7vIauUgjPNJ2f7rYg8KAmSw (9 cols: S.No | Module | Bug Description | Status | Recordings/Screenshot | Remarks | Log Trace | Test case | issue side). Give content **column-by-column** so the user can paste. (Drive reader can't target a tab by gid; ask for the header row if unsure.) Also keep `aiaccountant_tc_results.md` updated.

---

## 3. Tests run this session

| Test | Platform | Result |
|---|---|---|
| **AUTH-27** sign-out clears session/caches → Login | web + android | ✅ PASS (session file 4397→67B on android; F5/cold-relaunch stays on Login) |
| **AUTH-33** activate push = x-api-key only (no Bearer) | backend | ⚠️ CONFIRMED security weakness — job_ids also enumerable w/ shipped key → full unauth push chain (LOW pri, single-client) |
| **SCAN-5 / 6** sale/purchase routing + badge | android | ✅ PASS |
| **SCAN-9** Android gate → ML Kit scanner opens | android | ✅ PASS (+ SCAN-1 dialog, SCAN-11 cancel-no-job) |
| **SCAN-10** capture added + enqueue fires | android | ✅ PASS |
| **SCAN-20** parse endpoint unauthenticated | backend | ⚠️ CONFIRMED security (chains w/ AUTH-33; LOW pri) |
| **SCAN-24** end-to-end scan→parse→queue→drain | android | ✅ PASS |
| **SCAN-25 / 26** silent invoice drop (sale/purchase) | android | ⚠️ **CONFIRMED data-loss gap** |
| **SCAN-27** ingest-down silent loss | n/a | ⚠️ documented gap (equivalence to 25/26; not live-repro) |
| **SCAN-36** remote scan climbs/drains WEB badge | web (realtime) | ✅ PASS |
| **SCAN-39** duplicate purchase flagged (EMKAY) | android | ⚠️ observed (flagged, still enqueued) |
| **PUSH-37** push happy path | android | ❌ did NOT pass — push **failed at Tally** (see §4) |

---

## 4. KEY FINDINGS / BUGS (priority order for a single-client deploy)

1. **🔴 OCR stock-item CONCATENATION bug (flow blocker) — NEW, found during PUSH-37.**
   The parser merges multiple stock-item variants into ONE invalid "A + B + C + D" name → **Tally rejects the whole push** (`Stock Item '…' does not exist!`). Systemic — seen on ≥4 vouchers:
   - `STEELGRIP TAPE 3/4" BLUE + … RED + … GREEN + … YELLOW` (BALAJI `SALE-20260702073126`, the push tested)
   - `DIE 3/4" BSP + DIE 3/4" BSP + DIE 3/4" BSP + DIE 3/4" UNF + DIE 3/4" BSP` (BALAJI)
   - `KIS-III M35 M14 X 1.5 BH BOTTOMING TIN` (AIPL), `HEX HOLD KIT` (CP GRAT-EX)
   Impact: **vouchers with grouped/multi-variant line items can't be pushed.** Root cause is parse-side (handwritten/grouped rows collapsed into one item).

2. **🔴 Silent invoice drop (SCAN-25/26/27) — data-loss.** A scan that fails to parse (bad photo, unknown party, OCR miss, ingest/RunPod down) → **no push_queue row, no error, no record**; `scan_jobs` orphaned, badge sweeps at 300s. User sees nothing. Fix: surface a "couldn't read this invoice" / failed-scan record (orphaned scan_job >5min = usable signal).

3. **🟠 PUSH-49 partial-success — accounting integrity.** Observed a row with `created=1` **AND** a line error (Tally created a partial voucher). App success logic (`created≥1`) would show green success while a line item was dropped. Confirm/triage.

4. **🟡 PUSH-50 fail path — needs client confirmation.** Push→Tally reject→status `failed`→error surfaced inline. **Open Q:** did a red "push failed" **dialog** appear, or only the inline "Status: failed"? (Needed to close PUSH-50.)

5. **⚪ Security (LOW pri, single-client): AUTH-33 + SCAN-20** — unauthenticated push chain (open parse URL + shipped key + enumerable job_ids). Logged; deferred by user.

---

## 5. Artifacts

- Plan: `md_files/aiaccountant_backend_interaction_testplan_2026-06-30.md` (+ `.raw.json`, 494 cases)
- Interaction map: `md_files/aiaccountant_interaction_map_2026-06-30.md`
- Results log: `md_files/aiaccountant_tc_results.md` (per-test detail + evidence)
- Screenshots: `md_files/auth27_evidence/`
- Memory: `aiaccountant-backend-interaction-map` (harness, priorities, env), `feedback-recommend-dont-menu`

---

## 6. INSTRUCTIONS FOR NEXT CHAT (do these)

**A. Close the open PUSH-37 item (in progress):**
1. Get from user: did the **fail dialog** pop on the failed push? → log **PUSH-50**.
2. **Log the OCR-concatenation bug** (finding #1) as a high-priority row in the sheet + tc_results.md. Also log **PUSH-49** (finding #3).
3. Get a **clean PUSH-37 success**: either (a) **edit** the failed BALAJI voucher to remove/fix the concatenated STEELGRIP item then push, or (b) pick a voucher whose items all exist in Tally. Verify: `push_queue` narration→"Replara AI", pending→push_now→**pushed** + `tally_response.created≥1` + `pushed_at`; sheet closes → **sale success modal**; row moves queue→History; voucher in Tally Day Book. (Watch `status=failed` too — my earlier poller only watched push_now/pushed and missed the `failed` transition; poll all three.)

**B. Then continue HIGH-value FLOW tests (single-client priority):**
- **PUSH-30/31** — edit Save guarded by `status=pending` (watch the exact `push_queue.update … eq status pending`).
- **PUSH-39/40** — party-changed-but-not-all-items push block.
- **PUSH-49** — partial-success shown as green (reproduce deliberately).
- **QUEUE-1/5/9/10/16/29** — queue realtime (INSERT/UPDATE/DELETE, TOAST-omitted payload → "Unknown/₹0", edit-state markers, duplicate purchase).
- **HIST-18/19/38** — stored invoice image fetch (backend `/push-queue/:id/image/:page`), TOAST re-fetch.
- **RPT-22** — `K V ENTERPRISES` 409 duplicate-company report (probe reorder endpoint directly).
- **MAST-11/12/15** — customer/vendor pickers + 1000-row truncation (party unselectable → push blocked).

**C. Housekeeping the user asked for (pending):**
- **Bulk-format the already-PASSED rows** (AUTH-27, SCAN-5/6/9/10/24/36) into the sheet's 9-column layout for the **"AI Accountant App Issues"** tab (user said "later"). Ask for that tab's header row first if unsure it matches the sibling tab.

**D. Cleanup note:** orphaned `scan_jobs` test rows exist on yynuu (garbage scans `c1b5adf6`, `3bdb2e5b` + old ones) — harmless, ignored by 300s-windowed queries; leave or delete.

**Start next session by:** confirming the emulator (`adb devices`) + desktop TallyBridge/Tally are up, then resume at **§6.A step 3** (clean PUSH-37) unless the user redirects.
