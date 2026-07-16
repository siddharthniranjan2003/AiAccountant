# AI Accountant — Dev Handout (2026-06-10, session: caches · auth gate · payload fixes · duplicate flag)

Context handoff for a fresh chat. Covers **everything done after the previous compact** in this
session. All changes are **uncommitted** working-tree state (nothing committed since `711fd3c`,
plus the prior sessions' uncommitted files). Web was rebuilt + redeployed several times; all
shipped fixes are live on **https://aiaccountant-b60ed.web.app**.

> Companion docs at repo root: `handoff_2026-06-10_voucher_sheet_ux_fixes.md` (focus-loss,
> Enter-nav, earlier auth attempt) and `handoff_2026-06-08_pickers_editing_config.md`
> (two-project setup, picker RPCs, config centralization).

---

## 0. ⚠️ IMPORTANT correction — which Supabase project is live
`lib/core/config.dart` now points the client at **`yynuuysvjeipawzfbeme`**
(`https://yynuuysvjeipawzfbeme.supabase.co`), **NOT** the older `ztugwhevemibdrzqafyw` that earlier
handoffs/memory referenced. Confirmed via the Supabase MCP `list_projects` (only project visible)
and verified by querying `push_queue`. **Any DB work (RPCs, indexes, manual checks) must target
`yynuuysvjeipawzfbeme`.** The still-open join-version `get_sale_items_for_party` /
`get_purchase_items_for_party` + indexes task (from the 2026-06-08 doc) therefore needs to be
applied **here**, not on the old project.

Web hosting is unchanged: Firebase project **`aiaccountant-b60ed`**.

## 0.1 Build / deploy (unchanged)
- `flutter build web --release` → `firebase deploy --only hosting --project aiaccountant-b60ed`
  - PowerShell one-liner: `flutter build web --release; if ($?) { firebase deploy --only hosting --project aiaccountant-b60ed }`
- **Always hard-refresh after deploy** (Ctrl+Shift+R ×2, or DevTools → Application → unregister SW
  + clear site data) — the service worker repeatedly serves a stale bundle otherwise.
- If deploy fails "credentials no longer valid": run `! firebase login --reauth` (interactive), retry.

---

## 1. Caches: clear on logout, re-download on login
**Want:** logging out clears cached data; logging back in re-downloads what's needed.

**What's cached (in-memory singletons, loaded once at startup):**
- `StockItemsCache` — `from('stock_items').select('name, group_name, rate')` (the only *item* cache;
  used by the picker's "show all" + as the fallback when the party RPC fails)
- `CustomersCache` — `ledgers` where `group_name = 'Sundry Debtors'` (sale parties)
- `VendorsCache` — `ledgers` where `group_name = 'Sundry Creditors'` (purchase parties)

Not cached: party-specific item history (RPC, fetched fresh each open); `push_queue` (realtime);
scanned invoice images (`InvoiceImageStore`, on-disk, intentionally left alone).

**Change:**
- Added `clear()` (`items = []; isLoading = false;`) to `lib/data/stock_items_cache.dart`,
  `customers_cache.dart`, `vendors_cache.dart`.
- `lib/main.dart`: replaced the three unconditional startup `fetch()` calls with an
  **`authStateChanges()` listener** (single source of truth): on sign-in → `fetch()` all three;
  on sign-out → `clear()` all three. A `lastUid` guard skips redundant reloads when the stream
  re-emits the same user. Covers cold-start-with-session, login, and logout.

## 2. Android login "not persisting" / back → Login — fixed by making the auth gate authoritative
**Symptom:** on the Android app, after login, pressing back returned to Login (web was fine).
**Root cause (NOT Firebase):** `firebase_auth` persists natively on Android; this was a
navigation-stack bug. The app mixed a reactive `StreamBuilder(authStateChanges)` gate with
imperative `pushReplacement`/`pushAndRemoveUntil` calls that fought each other. `SplashScreen`
also unconditionally `pushReplacement(Login)` after 1400 ms, destroying the gate (a persistence
race). The device APK was also stale (only web had been rebuilt).

**Fix — reactive gate is the single authority** (no `PopScope` anywhere; pure nav):
- `lib/main.dart` gate: `waiting → SplashScreen`, `hasData → AccountantShell`, else → **`LoginScreen`**
  (was `SplashScreen`). Added `import 'features/auth/login_screen.dart';`.
- `lib/features/auth/splash_screen.dart`: **removed** the `Future.delayed(... pushReplacement(Login))`
  block (and its import). Splash is now a pure animation shown only during `waiting`.
- `lib/features/auth/success_screen.dart`: replaced `pushAndRemoveUntil(Shell, (r)=>false)` with
  `Navigator.of(context).popUntil((route) => route.isFirst)` — the auth flip already turned the
  gate route `/` into the Shell; popping reveals it. Removed unused `app_shell` import.
- `lib/features/auth/login_screen.dart`: `_goToSuccess` now `push(Success)` (was `pushReplacement`)
  so the auto-verify path doesn't destroy the gate route.
- `lib/features/profile/profile_screen.dart`: `_signOut` now just `await FirebaseAuth.signOut()`
  (removed the manual `pushAndRemoveUntil(Splash)` and the `context` param + splash import). The
  gate reacts → renders Login.
- `otp_screen.dart` unchanged (its `pushReplacement(Success)` replaces the pushed Otp route, fine).

**Resulting flows:** cold-start-signed-in → Splash→Shell (back exits); fresh login → Login→Otp→
Success→popUntil→`[/=Shell]` (back exits); logout → gate flips to Login. **The Android device must
be rebuilt** (`flutter build apk` / `flutter run`) for this to land — web has it.

## 3. Voucher edits not reaching `voucher_payload` — diagnosed + 2 fixes
Full lifecycle of edit/add/revert/save lives in `lib/features/queue/voucher_detail_sheet.dart`.
For Supabase rows, `_payload` is the **flat** voucher_payload (party_name, items, ledger_entries…)
+ `__row_id`/`__status`. Save (`_toggleEdit` "editing" branch) writes party_name/items/charges into
`_payload`, then `_persistEditsToSupabase` does
`update({'voucher_payload': cleanPayload}).eq('id', rowId).eq('status','pending')`.

**Verified against live `push_queue` rows:** `party_ledger_name` does NOT exist; `is_party_ledger`
is `false` on every entry → the **party line is identified solely by `ledger_name == party_name`**
(it's also the largest-abs entry). Items carry `unit:"NOS"`, `godown_name:"Main Location"`.
`inventory_ledger_name` present on all rows (so item-amount edits do rescale charges).

**Bug 1 (fixed) — vendor change wasn't propagated to `ledger_entries`.** Editing the vendor only
set top-level `party_name`; the party line kept the OLD name → pushed voucher posted against the
old ledger. Fix in `_writeChargesBack`: in the `identical(entry, partyEntry)` branch, also set
`updated['ledger_name'] = _editablePartyName` (trimmed, when non-empty).

**Bug 2 (fixed) — added items had no `unit`.** `_addItem` appended items without `unit`; the push
validator (`backend/src/routes/sync.ts` `normalizePushVoucherPayload`) **requires** a non-empty
`unit`, so any voucher with an added line was rejected. Fix: the appended map now includes
`'unit': 'NOS'` and `'godown_name': 'Main Location'`.

**Not fixed (noted):** party detection by largest-abs (works for all live rows); tax-ratio rescale
degrading when original inventory amount is 0 (not triggered by current data).

## 4. Duplicate vouchers — `invoice_exists` flag in the queue
**Want:** when `voucher_payload.invoice_exists == true` (a new boolean the backend WILL add — it's
**not on any row yet**, 0/100), the queue row (sale + purchase) shows **"Duplicate"**, is greyed
out, and tapping it shows a toast **"This Invoice Is Already In TallyPrime"** instead of opening the
sheet. False/absent → no change (safe default today).

**Change:**
- `lib/core/models.dart`: added `QueueEntry.invoiceExists` getter (reads
  `scanResult['invoice_exists']`, tolerant of bool or `"true"`). The value already flows via
  `push_queue_service.rowToEntry` spreading `voucher_payload` into `scanResult`.
- `lib/features/queue/queue_row_tile.dart`: `isDuplicate` folds into the grey-out opacity (0.56),
  and a red **"Duplicate"** label renders under the time (mirrors the failed/pushing label). InkWell
  tap stays active so the toast still fires.
- `lib/features/queue/queue_screen.dart`: `_openChallanSheet` short-circuits when `invoiceExists` —
  `ScaffoldMessenger` SnackBar with the message, then `return` (no sheet). (Chose SnackBar to match
  the app-wide pattern; the custom `ToastStack`/`ToastEntry` widgets exist but aren't wired into the
  shell.)

To test before the backend ships the key (live DB write — revert after):
`update push_queue set voucher_payload = voucher_payload || '{"invoice_exists": true}'::jsonb where id = '<row>';`

---

## 5. Files touched this session
- `lib/main.dart` (cache listener + gate→Login)
- `lib/data/stock_items_cache.dart`, `customers_cache.dart`, `vendors_cache.dart` (`clear()`)
- `lib/features/auth/splash_screen.dart`, `success_screen.dart`, `login_screen.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/queue/voucher_detail_sheet.dart` (vendor rename + added-item unit)
- `lib/core/models.dart` (`invoiceExists` getter)
- `lib/features/queue/queue_row_tile.dart`, `queue_screen.dart` (duplicate UI + toast)

`flutter analyze` clean on all touched files throughout.

## 6. Outstanding / next steps
- ⬜ **Commit the working tree** — large uncommitted state across multiple sessions (since `711fd3c`).
- ⬜ **Rebuild the Android APK** — §2 (auth) and §3 (payload) are Dart fixes that only landed on web;
  the device runs a stale build. `flutter build apk --release` or `flutter run`.
- ⬜ **Client DB task on `yynuuysvjeipawzfbeme`** — apply join-version `get_sale_items_for_party` /
  `get_purchase_items_for_party` + indexes (from the 2026-06-08 doc; project pointer corrected here).
- ⬜ **Backend** must start writing `voucher_payload.invoice_exists` for §4 to show in production.
- ◻ Optional: verify §3 vendor fix on a real push (party line renamed → posts to new vendor).
