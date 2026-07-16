# Session Handout — Sale Item Picker, Live Charges, Supabase Persist & Web Hosting

This covers everything done in this session (post-compact). Read top to bottom; it's
roughly chronological. Code lives in `lib/features/queue/voucher_detail_sheet.dart`
unless noted.

---

## 0. The core domain flow (important mental model)

- The app does **NOT** push vouchers to Tally itself.
- Sale/purchase queue rows come from the Supabase **`push_queue`** table via realtime.
- A separate app, **tallybridge**, polls `push_queue` for rows with `status = 'push_now'`
  and pushes those to **Tally Prime**.
- The **"Push To Tally"** button only flips a row `pending` → `push_now` (via a backend
  `activate` endpoint). It does not push.
- The **"Save"** button (added this session) persists edits back into the row's
  `voucher_payload` column while it's still `pending`.

`voucher_payload` is **flat** (no nesting). Top-level keys:
`date, party_name, voucher_type, voucher_number, reference, narration,
discount_total, inventory_ledger_name, stock_ledger_name, items[], ledger_entries[]`.

- `items[]` element: `stock_item_name, rate, quantity, unit, amount, discount_pct,
  batch_name, godown_name, destination_godown_name`
- `ledger_entries[]` element: `ledger_name, amount, is_party_ledger, is_deemed_positive`
- For a sale: `voucher_type` = `"GST SALE"`, `inventory_ledger_name` = `"GST SALE"`.
  Party ledger = the entry with the largest abs amount (== invoice Total).
  Sum of item `amount`s == the `GST SALE` ledger amount; `GST SALE + CGST + SGST` == Total.

`PushQueueService.rowToEntry` (`lib/data/push_queue_service.dart`) spreads the **entire**
payload into `entry.scanResult` and adds only `__row_id`, `__status`, `__source_payload`.
So the sheet's local `_payload` is a complete copy; stripping `__`-prefixed keys yields a
faithful full payload for writing back.

---

## 1. Sale item-edit dropdown → party-specific sales history (Supabase RPC)

**Goal:** in a **sale** voucher, the item picker should show items this party has actually
been sold before (with their last rate), not the full `stock_items` catalog. Fallback to
other parties' sales when this party has no history for an item.

### Supabase RPC `get_sale_items_for_party(p_party_name text)`
Returns `(stock_item_name, rate, discount_pct, source)` where `source` is
`'same_party'` (this party's own sales, latest rate per item) then `'different_party'`
(other parties' sales for items not already covered). Both filter `rate > 0`.

**Two bugs were found & fixed here (RPC was silently crashing → app fell back to catalog,
which is why ₹0 rates and catalog group-names appeared):**
1. **Ambiguous column** — `stock_item_name` in `NOT IN (SELECT stock_item_name ...)`
   clashed with the function's `RETURNS TABLE` output column. Fixed by aliasing CTE
   columns (`item_name`, `item_rate`, `item_disc`, `item_source`).
2. **Wrong voucher_type** — filtered `voucher_type = 'Sales'`, but the data stores sales
   as **`'GST SALE'`**. Fixed to `voucher_type ILIKE '%SALE%'` (mirrors the app's own
   `voucher_type.contains('SALE')` classification).

Verified for `BALAJI H/W AGENCIES`: 6,820 items (478 same_party + 6,342 different_party),
min rate ₹0.09 — no zeros.

Migrations applied (via Supabase MCP): `get_sale_items_for_party`,
`fix_get_sale_items_ambiguous_column`, `fix_sale_voucher_type_match`. Also fixed the
related `get_latest_rates_for_party` (used by the Google Apps Script) the same way
(`fix_latest_rates_sale_voucher_type`) and simplified it to read `voucher_items` directly
(it already has `party_name`, `date`, `voucher_type`) instead of joining `vouchers`.

### Flutter changes
- `lib/data/stock_items_cache.dart` — `StockItem` gained `source` (`''` | `same_party` |
  `different_party`) and `discountPct`. New factory `StockItem.fromSaleRow(row)` maps the
  RPC result; `groupName` shows `"Other vendors"` for `different_party`, blank otherwise.
- `_StockItemPickerSheet` — now takes `partyName` + `isSale`. When `isSale && partyName != null`
  it calls `Supabase...rpc('get_sale_items_for_party', {'p_party_name': partyName})`, shows
  a spinner while loading, and **falls back to `StockItemsCache` (catalog) on error**.
  (Purchase keeps using the catalog as before.)
- `_SheetItemRow` — gained `partyName` + `isSale`, passes them to the picker.
- `_buildSummaryView` threads `partyName` and `_isSale` into each `_SheetItemRow`.

### On item selection, write-back
In `onStockItemSelected`: writes `stock_item_name`, `rate`, **and `discount_pct`** from the
selected item, then recomputes `amount = qty * rate * (1 - disc/100)`.
The Disc cell needed `key: ValueKey('disc_$disc')` (like rate/amount) so the uncontrolled
`TextFormField` rebuilds with the new value.

---

## 2. Live Charges recompute when items change

When any item changes (swap, qty, rate, disc), the **Charges** block recomputes live.

State added: `_taxRatios: Map<String,double>` and `_inventoryLedgerName`.
- Captured **once on edit entry**: for each non-inventory ledger,
  `ratio = ledgerAmount / gstSaleAmount` (e.g. CGST ≈ 0.09, SGST ≈ 0.09).

`_recomputeChargesFromItems()`:
- `GST SALE` ← sum of `_editableItems` amounts
- `CGST`/`SGST` ← `newGstSale * ratio` (proportional scaling — user's chosen behavior)
- `Discount` ← sum of `qty * rate * disc_pct / 100`
- `Total` ← sum of all `_editableLedgers` amounts

Called from both `onStockItemSelected` and `onItemChanged`.

**Critical fix:** `_computeCharges()` previously read `inventory_ledger_name` only from
`_voucher` (nested), which is `null` for flat Supabase payloads → `_inventoryLedgerName`
was always null → recompute exited on its guard. Now reads
`voucher?['inventory_ledger_name'] ?? _p['inventory_ledger_name']`.

UI plumbing fixes:
- `_SheetEditableRow` got `super.key`; added `ValueKey` to ledger rows
  (`ledger_<name>_<amount>`), Discount (`discount_<v>`), Total (`total_<v>`) so the
  uncontrolled fields rebuild when amounts change.
- `isPercent` now also requires `amount < 100` so rupee values like 144213.95 render as ₹
  (not `%`). Same guard added to `_chargeValue` (view mode).
- Rounding: editable cells (`_EditableNumCell` and `_SheetEditableRow`) use
  `toStringAsFixed(2)` so `₹1585112.6899999997` shows as `₹1585112.69` (underlying value
  keeps full precision).

---

## 3. Fresh-scan response sheet — view-only

When a sale/purchase PDF is scanned, the bottom sheet (opened with `pendingPayload`) is now
**view + image-slider only**:
- Edit / Add / Revert buttons hidden via `if (widget.pendingPayload == null)`.
- **Push To Tally** hidden too (`if (!_loading && widget.pendingPayload == null)`).
- Discard was already hidden (no `onDiscard` passed on the scan path).

The queue-opened sheet (existing row) is unchanged and fully editable.

---

## 4. Save → persist edited `voucher_payload` to Supabase

On **Save** (the `_isEditing` → off branch of `_toggleEdit`):
1. Write `party_name` + `items` into a local `updated` copy (existing behavior).
2. `_writeChargesBack(updated)` — rebuilds `ledger_entries`: party entry (largest abs
   amount) ← `_editableTotal`; other ledgers matched by `ledger_name` ← recomputed amounts;
   **original sign + `is_party_ledger`/`is_deemed_positive` preserved**. Sets
   `discount_total = _editableDiscount`.
3. `_payload = updated`.
4. `_persistEditsToSupabase(updated)` (fire-and-forget, async):
   - Bail if `__row_id` empty (seed/fresh-scan rows).
   - `cleanPayload = Map.from(updated)..removeWhere((k,_) => k.startsWith('__'))`.
   - `update({'voucher_payload': cleanPayload}).eq('id', rowId).eq('status','pending').select('id')`.
   - **Confirm/warn snackbar** (captured `ScaffoldMessenger` before the await):
     "Changes saved." if a row matched, else "Couldn't save — this voucher may already be
     queued for push.", or a generic error on exception.

**Edit gating:** entering edit mode is blocked when `_status != 'pending'`
(snackbar: "This voucher is already queued for push and can't be edited."). `_status` is
kept live by `_subscribeToStatus`.

### Safety properties (why this is safe to write directly from the client)
- **RLS verified:** `push_queue` has RLS enabled but a single policy
  "Service role full access" that is actually `TO public USING true WITH CHECK true cmd=ALL`
  — so the anon/publishable-key client **is** allowed to UPDATE. No backend change needed.
- **Status guard** (`.eq('status','pending')`) — a concurrent flip to `push_now` by
  tallybridge makes the write a 0-row no-op (surfaced as the warning snackbar).
- **Complete payload** — full original payload minus `__` meta; tallybridge sees the same
  shape it expects. Only the `voucher_payload` column is touched; `source_payload`/`status`
  untouched.

---

## 5. Web hosting (Firebase Hosting) — DONE, with a caching caveat

**Decisions:** host on **Firebase Hosting**; security = "swap key only (minimum)".

### Security fix (was critical)
`lib/main.dart` initialized Supabase with **`SUPABASE_SERVICE_KEY`** (service-role / god
key). On web that would ship in the JS bundle to every browser. Also `.env` was a bundled
**Flutter asset** (`pubspec.yaml`), so it shipped to the browser regardless. Fixes:
- `main.dart`: removed `dotenv`; hardcoded the non-secret `_supabaseUrl`
  (`https://yynuuysvjeipawzfbeme.supabase.co`) and `_supabaseAnonKey`
  (`sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl`) — same publishable key already
  hardcoded in `ApiClient`.
- `pubspec.yaml`: removed `.env` from `assets:` so no secret bundles into the build.

### Build & deploy
- `flutter build web --release` compiles fine (ML Kit document scanner compiles but is inert
  on web — scanning already guarded by `if (!isAndroid)` snackbar in `app_shell`).
- Created `firebase.json` (`public: build/web`, SPA rewrite, cache headers) and `.firebaserc`
  (default project `aiaccountant-b60ed`).
- Deployed: **https://aiaccountant-b60ed.web.app**.

### Two issues hit & fixed
1. **Blank page** — `firebase_options.dart` had `if (kIsWeb) throw UnsupportedError('Web not
   supported')`. Created a Firebase **web app** (`firebase apps:create web`), added
   `DefaultFirebaseOptions.web` (config below), and changed `currentPlatform` to
   `if (kIsWeb) return web;`. Web app id: `1:845558047543:web:3049c5ea80e79809ad30b2`.
2. **Stale service worker** — Hosting served `flutter_service_worker.js` / `index.html` with
   `Cache-Control: max-age=3600`, so browsers kept running the first (broken) build. Added
   `no-cache, no-store, must-revalidate` headers in `firebase.json` for
   `index.html, flutter_service_worker.js, flutter_bootstrap.js, main.dart.js` and `/`
   (these entry files are NOT content-hash-named, so they must not be HTTP-cached).

### Verified state of the deployment
- Deployed `main.dart.js` **SHA-256 == local build SHA-256**
  (`76d2bfc3315aae1c53e7d7cdc3c3e1489b299f9770d53d4f384cf07b39d51309`), 2,970,592 bytes.
- Deployed bundle contains the web Firebase config and **0** occurrences of the old
  `"Web not supported"` throw.
- A **local debug build** (`flutter run -d web-server --web-port 8091`) loaded the full app
  correctly (queue, Supabase data, nav) — proving the app code works on web.

**Conclusion:** the latest correct build IS deployed. Any remaining blank/old-error in a
specific browser is that browser running a **stale cached** copy. Fix on the client once via
Incognito (Ctrl+Shift+N) or DevTools → Application → Service workers → Unregister + "Empty
Cache and Hard Reload". Going forward the no-cache headers prevent recurrence.

---

## Key config values (non-secret, safe to ship)

- Supabase project: `yynuuysvjeipawzfbeme`, URL `https://yynuuysvjeipawzfbeme.supabase.co`
- Supabase publishable key: `sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl`
- Firebase project: `aiaccountant-b60ed` (number 845558047543)
- Firebase web app id: `1:845558047543:web:3049c5ea80e79809ad30b2`
- Firebase web apiKey: `AIzaSyAJwvt3pBHqF_g2yrDj6HAVqNZNLT77Jhg`,
  authDomain `aiaccountant-b60ed.firebaseapp.com`, measurementId `G-FE8S1YSHQF`
- Cloud Run backend: `https://tallybridge-backend-950406969086.asia-south1.run.app`
- Hosting URL: `https://aiaccountant-b60ed.web.app`

---

## Files touched this session

- `lib/features/queue/voucher_detail_sheet.dart` — picker (party-specific), discount_pct
  write-back, live charges recompute (`_recomputeChargesFromItems`, `_taxRatios`,
  `_inventoryLedgerName`), `_computeCharges` flat-payload fix, ValueKeys + `isPercent<100`
  + 2-dp rounding, fresh-scan button hiding, `_writeChargesBack`, `_persistEditsToSupabase`,
  edit gating on non-pending.
- `lib/data/stock_items_cache.dart` — `StockItem.source` + `discountPct` + `fromSaleRow`.
- `lib/main.dart` — drop dotenv, hardcode URL + publishable key.
- `lib/firebase_options.dart` — add `web` options; `currentPlatform` returns `web` on web.
- `pubspec.yaml` — remove `.env` from assets.
- `firebase.json`, `.firebaserc` — new (hosting + cache headers).
- Supabase migrations: `get_sale_items_for_party` (+ 2 fixes), `get_latest_rates_*` fixes.

`flutter analyze` is clean after each change.

---

## Git / commit state

- Commit **711fd3c** ("Add sale item picker with party-specific history, queue UI cleanup,
  and Cloud Run backend") was pushed to `project_reorg` earlier in the session and covers
  the first slice of UI work.
- **Uncommitted** (as of writing): the live-charges recompute, `_writeChargesBack`,
  `_persistEditsToSupabase`, edit gating, fresh-scan view-only changes, and **all web-hosting
  changes** (`main.dart`, `firebase_options.dart`, `pubspec.yaml`, `firebase.json`,
  `.firebaserc`). These still need a commit.

---

## Open / pending items

1. **Duplicate line items** (raised, unresolved): some `voucher_payload.items` arrays contain
   exact duplicate entries (e.g. `HSS TAP 4BA SEC TOTEM` ×2, `HSS TAP 5BA SEC TOTEM` ×2,
   `L HANDLE` ×2 in the `SHREE SHYAM HARDWARE STORE` voucher). The app renders `items` as-is
   (no dedup). Need clarification on desired behavior (dedupe in app? backend issue? a
   Flutter duplicate-key error?). **Not yet actioned.**
2. **RLS deferred** — 14 tables have RLS **disabled** (vouchers, voucher_items, ledgers,
   stock_items, etc.). With the app now on a public web URL using the anon key, those tables
   are world-readable. The user chose "swap key only" and deferred enabling RLS + policies.
   This is the biggest outstanding security item.
3. **Manual charge-field edits don't cascade** — typing directly into CGST/SGST/Discount
   does not re-run `_recomputeChargesFromItems`; only *item* changes trigger recompute (by
   design, per the request). Revisit if full cascade is wanted.
4. **Local save vs Supabase save** — `queue_screen._savedEdits` tracks edits in memory
   independently of the Supabase write. If the Supabase write fails, the local copy still
   shows the edit until a pull-to-refresh reverts it.
5. **Older deferred items** (from earlier sessions, still open): duplicate queue rows
   (transient `*_scan_*` + `supabase_*` realtime), invoice-image persistence to disk keyed by
   row id, history-screen image tab.

---

## How to redeploy web (quick reference)

```
flutter build web --release
firebase deploy --only hosting
```

Verify it's live and matches local:
```
curl -s https://aiaccountant-b60ed.web.app/main.dart.js | sha256sum
sha256sum build/web/main.dart.js
```
If a browser still shows an old build, it's client cache — use Incognito or unregister the
service worker + "Empty Cache and Hard Reload".
