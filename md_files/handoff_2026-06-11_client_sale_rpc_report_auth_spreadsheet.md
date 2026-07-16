# AI Accountant — Dev Handout (2026-06-11, session: client sale RPC fix · report auth · spreadsheet wrap)

Context handoff for a fresh chat. Covers **everything done after the last compact** in this session.
Three threads: (1) fixed the **client** Supabase sale-item RPC timeout, (2) diagnosed the Report
screen **"Unauthorized"** (turned out to be wrong login, not a bug), (3) shipped a **spreadsheet
cell-wrapping** UI change to web.

> Companion docs at repo root (earlier sessions): `handoff_2026-06-10_amount_recalc_web_ui.md`,
> `handoff_2026-06-10_caches_auth_payload_duplicate.md`, `handoff_2026-06-10_voucher_sheet_ux_fixes.md`,
> `handoff_2026-06-08_pickers_editing_config.md`.

---

## 0. Ground truth (verify before any DB / endpoint work)
- **TWO Supabase projects are in play — do not confuse them:**
  - **`yynuuysvjeipawzfbeme`** = the **live app** project. Set in `lib/core/config.dart` (`supabaseUrl`).
    The Flutter app connects here. anon/publishable key only; service-role never ships.
  - **`ztugwhevemibdrzqafyw`** = the project in **`.env_clinet`** (repo root). This is the one with the
    real Tally history (`vouchers` + `voucher_items`, ~96k item rows). **This is where the sale-RPC fix
    below was applied.** (Older note called this the "old" project — but it holds the live client data
    and is the one whose item-picker RPCs matter.)
- **Web hosting: Firebase project `aiaccountant-b60ed`** (also the Firebase **Auth** project for both
  web and Android — `lib/firebase_options.dart`).
- Build + deploy (PowerShell): `flutter build web --release; if ($?) { firebase deploy --only hosting --project aiaccountant-b60ed }`
- **Always hard-refresh after deploy** (Ctrl+Shift+R ×2) — service worker serves a stale bundle.
- Supabase MCP is treated read-only; **DB writes require explicit user confirmation** (the auto-mode
  classifier blocks `apply_migration`/DDL to the client DB unless the user explicitly authorizes the
  specific migration — in this session the user ran the migration himself in the dashboard SQL editor).

---

## 1. How sale-item editing fetches from Supabase (mental model)
In `lib/features/queue/voucher_detail_sheet.dart`:
- Tapping an item in edit mode opens **`_StockItemPickerSheet(partyName, isSale)`** (~:1901).
- `_load()` (~:2221): if "All items" toggled or no party → uses in-memory **`StockItemsCache`** (full
  `stock_items` catalog, downloaded once at login in `main.dart`). Otherwise → `_fetchPartyItems()`.
- `_fetchPartyItems()` (~:2235) calls the RPC **`get_sale_items_for_party`** (sale) /
  `get_purchase_items_for_party` (purchase) with `{'p_party_name': partyName}`, maps rows via
  `StockItem.fromSaleRow` (`stock_items_cache.dart:26` — reads `stock_item_name`, `rate`,
  `discount_pct`, `source`).
- **Critical fallback (`:2253`):** any RPC error is swallowed → falls back to the full catalog. So a
  slow/broken RPC silently degrades to "show the whole catalog," with **no error shown**.
- Picking an item → `onStockItemSelected` (`:1303`) writes name/rate/discount_pct and recomputes
  `amount = qty·rate·(1−disc%/100)`, then `_recomputeChargesFromItems()`.
- The full REST URL (e.g. `…/rest/v1/rpc/get_sale_items_for_party`) is **never literal in code** —
  the supabase client builds it from `Config.supabaseUrl` + `/rest/v1/rpc/` (baked into the
  `postgrest` package) + the rpc name.

---

## 2. THE FIX — client sale RPC was timing out ✅ APPLIED (user ran it)
**Project: `ztugwhevemibdrzqafyw`.** Pulled both RPC definitions live and compared:

- **`get_purchase_items_for_party`** (was fine): joins `vouchers`, **filters party in the WHERE**,
  `same_party` only → fast (probe returned instantly).
- **`get_sale_items_for_party`** (was broken): **no party filter in WHERE** — it scanned **all sale
  line-items for every customer**, joined `vouchers`, sorted, and used the party only in `ORDER BY`
  (`(party_name ILIKE p_party) DESC, date DESC`) to prefer same-party rows, tagging others
  `different_party` ("Other vendors" feature). On ~74.5k sale items this **exceeded the ~8s statement
  timeout → HTTP 500 (code 57014)** → app silently fell back to the catalog. (curl reproduced: sale =
  500 timeout, purchase = `[]` 200.)

**Data facts (project `ztugwhevemibdrzqafyw`):** `voucher_items` = 96,680 rows; sale line-items =
74,541; sale vouchers = 24,525. On `voucher_items`: `party_name` ✅ fully populated, `date` ✅ populated,
but **`voucher_type` is NULL on every row (0 populated)** — which is *why* the functions join to
`vouchers` for `voucher_type`. So the live project's flattened single-table form **cannot** be copied
verbatim here; the JOIN must stay.

**Why indexes alone couldn't fix it:** (a) `voucher_type ILIKE '%SALE%'` has a leading wildcard → not
btree-indexable; (b) no party filter → it must scan all sales by design. The only real fix is a logic
change.

**The applied change (only `get_sale_items_for_party`; purchase untouched):**
```sql
CREATE OR REPLACE FUNCTION public.get_sale_items_for_party(p_party_name text)
RETURNS TABLE(stock_item_name text, rate numeric, discount_pct numeric, source text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT ON (vi.stock_item_name)
    vi.stock_item_name, vi.rate, vi.discount_pct, 'same_party'::text
  FROM voucher_items vi
  JOIN vouchers v ON v.id = vi.voucher_id
  WHERE lower(v.party_name) = lower(p_party_name)   -- ← party filter (the fix)
    AND v.voucher_type ILIKE '%SALE%'
    AND vi.rate IS NOT NULL AND vi.rate > 0
  ORDER BY vi.stock_item_name, v.date DESC;
END; $$;
```
Now behaviorally identical to the **live** project (party-filtered, `same_party` only, fast),
adapted to the client's join schema.

**Trade-off accepted:** the **"Other vendors" (`different_party`) fallback is gone** — items the
customer never bought before no longer appear in the sale picker. (The app's `StockItem.fromSaleRow`
still has `different_party` → "Other vendors" grouping logic, but no RPC returns it now; effectively
dead, same as the live project.)

**Verification (live):** `get_sale_items_for_party('BALAJI H/W AGENCIES')` — the busiest sale customer
(1,068 sale lines) — now returns **468 distinct items in ~0.95s** (was an 8s timeout/500). Confirmed
via `EXPLAIN ANALYZE`.

**Note:** `date` is used only for `ORDER BY` (to pick each item's most-recent rate via `DISTINCT ON`);
there is **no date cutoff** — all-time history is included.

### Optional, NOT applied — speed-up
~0.95s is fine but it seq-scans all 24.5k sale vouchers because `lower(v.party_name)=lower(p_party)`
can't use `idx_vouchers_company_party`. A functional index drops it to ~tens of ms and also helps the
purchase RPC (purely additive, no function change):
```sql
CREATE INDEX IF NOT EXISTS idx_vouchers_lower_party ON public.vouchers (lower(party_name));
```

---

## 3. Report screen "Failed to load report: Exception: Unauthorized" — RESOLVED (no code change)
**Symptom:** tapping any Report insight (e.g. `/act_now`) → snackbar "Failed to load report:
Exception: Unauthorized" on **web**; **worked on mobile**.

**Path:** `report_screen.dart:56` → `ApiClient.getRaw('/api/sync/reorder-levels/<reportId>', {company_name:'K V ENTERPRISES', format:'csv'})`
→ Cloud Run backend `https://tallybridge-backend-950406969086.asia-south1.run.app`. `ApiClient`
(`lib/services/api_client.dart`) sends `x-api-key` + (if present) `Authorization: Bearer <Firebase ID
token>`, and throws `Exception('Unauthorized')` on **any HTTP 401**, discarding the body.

**Diagnosis steps:** curl proved the backend's real gate is the **Firebase Bearer token** (x-api-key
alone → 401). DevTools on web showed the failing request **did** carry a valid `Authorization: Bearer`
(issuer `securetoken.google.com/aiaccountant-b60ed`, not expired) + the api-key + correct company, and
the CORS preflight returned 204. So the client was correct — the backend was rejecting an
authenticated request, i.e. an **authorization** decision (user not provisioned for company
`K V ENTERPRISES`).

**Resolution:** user confirmed **"it worked with right credentials"** — it was simply the wrong
account logged into web. **No code change.** (`company_name: 'K V ENTERPRISES'` is still hardcoded in
`report_screen.dart` — fine as long as the logged-in user is authorized for it.)

---

## 4. Spreadsheet cell wrapping ✅ SHIPPED (web rebuilt + deployed)
**File: `lib/shared/spreadsheet_sheet.dart`**, class `SpreadsheetGridRow` (the single render point for
both grid variants; used by the report bottom-sheet `AppSpreadsheetSheet`).

**Want:** column headers (`sales_qty`, `purchas…`, `closing_…`, `scenario…`) and cells (`STARVE …`,
long item names) were truncating with `…`; show the **full string**, wrapping to extra lines when the
column is too narrow.

**Change:** removed `maxLines: 1` + `TextOverflow.ellipsis`, set `softWrap: true`; wrapped the cell
row in **`IntrinsicHeight`** + `CrossAxisAlignment.stretch` and each cell's `Text` in an `Align`
(center for the row-number col, centerLeft otherwise) so vertical dividers stay full-height and text
stays vertically centered across cells that wrap to different line counts.

**Bug hit + fix:** first attempt used `CrossAxisAlignment.stretch` **without** `IntrinsicHeight` →
inside the vertical `ListView` the row had no height to stretch to → cells collapsed to 0 height →
**blank white grid**. Wrapping in `IntrinsicHeight` gave the row a concrete height and fixed it.

`flutter analyze lib/shared/spreadsheet_sheet.dart` clean. Built + deployed to `aiaccountant-b60ed`
(live). Minor open nicety: snake_case headers break mid-token (`closing_st`/`ock`); could insert
zero-width breaks after `_` to break as `closing_`/`stock` — not done (awaiting user).

---

## 5. Reference facts surfaced this session
- **Push-to-Tally URL** (`config.dart:21`, separate Cloud Run service, own key `activateApiKey`):
  `https://tallybridge-backend-xx3yz3b3kq-el.a.run.app/api/sync/push-queue/activate`
- **`backend/` folder = reference/source only — NOT touched this session.** Tracked (43 files), git
  status clean. It's the Node/TS source for the deployed `tallybridge` Cloud Run backend (`src/`,
  `dist/`, `package.json`, `full_schema.sql`, `supabase_schema_v*.sql`). All "backend" work this
  session was via HTTP curl to deployed URLs + Supabase MCP, never this folder. **Lead for later:** the
  report auth logic and the canonical RPC/schema definitions almost certainly live in `backend/src` and
  `backend/full_schema.sql`.

---

## 6. Files touched this session
- `lib/shared/spreadsheet_sheet.dart` — cell wrapping (IntrinsicHeight + stretch + Align; removed
  maxLines/ellipsis; softWrap). **Built + deployed.**
- **DB `ztugwhevemibdrzqafyw`** — `get_sale_items_for_party` replaced (party filter added). **Applied
  by the user in the dashboard.** Original definition is recoverable (it was the no-party-filter
  `different_party` join version).
- No other client code changed. Report "Unauthorized" needed no code change.

---

## 7. Outstanding / next steps (carried + new)
- ◻ **Verify the sale picker in-app** — open a sale voucher edit, tap an item → should now show that
  customer's last-sold items (not the full catalog). Confirm the "Other vendors" loss is acceptable.
- ◻ **Optional** `idx_vouchers_lower_party` functional index on `ztugwhevemibdrzqafyw` (§2) to take the
  sale RPC from ~0.95s → ~tens of ms (user can run it in the dashboard).
- ⬜ **Commit the working tree** — still nothing committed since `711fd3c` on branch `project_reorg`;
  large multi-session diff including this session's `spreadsheet_sheet.dart`.
- ⬜ **Rebuild the Android APK** — all recent fixes are web-only/DB-only; device runs a stale build.
- ◻ Carried from prior handout: confirm backend purchase push tolerates seeded `discount_pct` +
  written `discount_total`; backend should write `voucher_payload.invoice_exists` for the Duplicate
  flag; review web screens for clip/wrap under the global +40% font scale.
- ◻ If the report 401 recurs with the *right* account, the answer is in `backend/src` (what it
  validates) / Cloud Run logs — not the client.
