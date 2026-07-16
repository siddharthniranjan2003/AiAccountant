# AI Accountant — Dev Handout (2026-06-10, session: inline amount recalc · web UI polish)

Context handoff for a fresh chat. Covers **everything done after the last compact** in this session.
All changes are **uncommitted** working-tree state (nothing committed since `711fd3c`, plus prior
sessions' uncommitted files). Web was rebuilt + redeployed after each change; everything below is
**live on https://aiaccountant-b60ed.web.app**.

> Companion docs at repo root (earlier sessions): `handoff_2026-06-10_caches_auth_payload_duplicate.md`,
> `handoff_2026-06-10_voucher_sheet_ux_fixes.md`, `handoff_2026-06-08_pickers_editing_config.md`.

---

## 0. Ground truth (verify before any DB / endpoint work)
- **Live Supabase project: `yynuuysvjeipawzfbeme`** (`https://yynuuysvjeipawzfbeme.supabase.co`),
  set in `lib/core/config.dart`. NOT the old `ztugwhevemibdrzqafyw`. anon/publishable key only in
  client; service-role key must never ship. Supabase MCP is treated read-only (writes need user OK).
- **Web hosting: Firebase project `aiaccountant-b60ed`**.
- Build + deploy (PowerShell): `flutter build web --release; if ($?) { firebase deploy --only hosting --project aiaccountant-b60ed }`
- **Always hard-refresh after deploy** (Ctrl+Shift+R ×2 / unregister SW) — the service worker serves
  a stale bundle otherwise.
- Single file for almost all of this session: **`lib/features/queue/voucher_detail_sheet.dart`**
  (plus `lib/main.dart` for the web font scale).

---

## 1. How the voucher Charges recompute works (mental model — applies to sale AND purchase)
On entering Edit (`_toggleEdit`), the sheet snapshots **tax ratios** once, anchored to the inventory
ledger (the rupee line — "GST Sale" for sale, "PURCHASE GST" for purchase):
`_inventoryLedgerName = inventory_ledger_name`; `_taxRatios[name] = abs(ledgerAmount) / abs(invLedgerAmount)`.

On any item change, `_recomputeChargesFromItems()` rescales from the new sum of item amounts:
- **inventory ledger (GST Sale / PURCHASE GST)** = `Σ item['amount']`
- **each tax ledger (CGST/SGST/IGST)** = `Σ amounts × frozen ratio`  ← NOT a real tax calc; it's a
  proportional scale, ratio fixed at edit entry.
- **Discount** = `Σ qty·rate·disc%` (computed directly from item fields; independent)
- **Total** = `Σ` of all breakdown ledger abs amounts (= inventory + taxes). **Discount is NOT
  subtracted** from Total (the per-item `amount` already nets the discount).
- Early-returns if `_inventoryLedgerName == null` or no editable ledgers.

Everything keys off `Σ item['amount']` actually moving. That was the root bug fixed this session.

---

## 2. THE BUG (diagnosed) — inline Qty/Disc/Rate edits didn't recompute the line amount
In `_SheetItemRow`, the inline Qty/Disc/Rate `onChanged` handlers wrote only the single field and
called `onItemChanged` — they **never recomputed `item['amount']`**. Since Charges derive from
`Σ item['amount']`, nothing rescaled (only the Discount line moved, since it's computed from
qty·rate·disc% directly). Editing the **Amount** cell directly always worked (it writes `amount`).
Two existing paths already did it right: `_addItem` and `onStockItemSelected`
(`amount = qty·rate·(1 − disc%/100)`).

---

## 3. FIX 3a — Sale: recompute amount on inline edits  ✅ shipped
Added `_recalcAmount()` to `_SheetItemRow` and called it in the Qty/Disc/Rate handlers (after the
field write, before `onItemChanged`). Amount cell left as direct edit. The Amount cell auto-refreshes
via `_EditableNumCell.didUpdateWidget` when `initial` changes.

## 4. FIX 3b — Purchase: same recalc  ✅ shipped (this is the most subtle change)
**Data reality (confirmed live, pending purchase rows, project `yynuuysvjeipawzfbeme`):**
- 68 pending purchase rows. **50 carry NO discount field** — the discount is baked into `amount`
  (e.g. rate 950 × qty 20 = 19,000 but `amount` = 11,400 ≈ 40% off). 18 carry `discount_pct`.
  **None carry a rupee `discount`.** Quantity key = `quantity` (same as sale).
- All 68 have `inventory_ledger_name` + `ledger_entries` (so charges rescale never early-returns);
  19 have `discount_total`.

A literal copy of the sale fix would treat absent `discount_pct` as 0 and **drop the baked-in
discount** on those 50 rows. So the fix **derives the implicit discount** and makes it the single
source of truth. Per user decision: derived discount is shown **everywhere (read-only view + edit)**.

Four edits, all in `voucher_detail_sheet.dart`:
1. **`_recalcAmount()`** — removed the `if (!isSale) return;` gate (now runs for both). Formula
   reads `quantity ?? qty`, `rate`, `discount_pct`.
2. **Edit-entry seeding in `_toggleEdit`** (right after `_editableItems = items.map(...).toList()`):
   for each item lacking `discount_pct`, when `qty*rate > 0` set
   `discount_pct = ((1 - amount/(qty*rate)) * 100).clamp(0, 100)` at **full precision** (so
   `_recalcAmount` reproduces the original amount exactly). No-op when already present / for sale.
3. **Per-item display fallback** in `_SheetItemRow.build` — `discValue` now derives from
   `(1 - amount/(qty*rate))*100` (clamped) when there's no `discount_pct` and no rupee `discount`, so
   the Disc column shows the real % in read-only view (was 0%).
4. **`_computeCharges` discount fallback** — when neither `_p` nor `voucher` has `discount_total`,
   each item contributes `max(0, qty*rate - amount)` (instead of only the rupee `discount` field), so
   read-only Charges "Discount" shows the real total. Equals `_recomputeChargesFromItems`'
   `newDiscount` once `discount_pct` is seeded → view and edit agree.

**⚠️ Persistence side effect:** on Save, `_editableItems` (now carrying seeded `discount_pct`) is
written to `voucher_payload.items` and `_writeChargesBack` sets `discount_total`. So saved purchase
payloads **gain explicit `discount_pct` + `discount_total`**; `amount` is unchanged and self-consistent
(`amount = qty·rate·(1−disc/100)`), so rupee totals are unchanged. **Open item: confirm the backend
purchase push tolerates the new fields** (one real push). Edge case: a line with `amount > qty*rate`
(markup) clamps to 0% — none in current data.

---

## 5. Web UI polish (all gated to web; phone layout unchanged)  ✅ shipped
Constants live at the top of `voucher_detail_sheet.dart`.
1. **Item column no longer stretches.** Was `Expanded` on web (pushed numeric columns to the far
   right). Now fixed `_kItemColWideW` via `_itemCell` + the table header. Numeric columns sit next to
   the name.
2. **Sheet body centered on web.** Added `_centerOnWide(wide, child)` (`Align.topCenter` +
   `ConstrainedBox(maxWidth: _kSheetContentMaxW)`) wrapping the summary `ListView`. Phones = full width.
3. **+40% font on web.** `lib/main.dart` `MaterialApp.builder` wraps the app in
   `MediaQuery(textScaler: TextScaler.linear(1.4))` **only when `kIsWeb`** → scales ALL text app-wide
   (routes + modal sheets). Required `import 'package:flutter/foundation.dart' show kIsWeb;` in
   `main.dart`.
4. **Table sized for the bigger font.** On web, the fixed column widths and the centered max width are
   scaled: `_kItemColWideW/_kQtyColW/_kDiscColW/_kRateColW/_kAmountColW = kIsWeb ? base*1.4 : base`
   (delete col unchanged), and `_kSheetContentMaxW = kIsWeb ? 1080 : 800`. Required the same `kIsWeb`
   import in `voucher_detail_sheet.dart`. (`kIsWeb` is const, so the const ternaries compile.)

> The 40% scale is **global on web** — it affects every screen (queue, history, reports, nav,
> buttons). The voucher sheet is sized for it; other screens use flexible layouts but should be eyed
> for any wrapped/clipped text. It's one number (`TextScaler.linear(1.4)`) to dial.

---

## 6. Verification done
- `flutter analyze lib/features/queue/voucher_detail_sheet.dart` (and `lib/main.dart`) clean after
  every change.
- Each change rebuilt (`flutter build web --release`) + deployed to `aiaccountant-b60ed`; build green.
- Live behavior not yet eyeballed by me on-device — recommend a hard-refresh pass over a sale voucher
  (edit qty → amount + GST/CGST/SGST/Total move) and a no-discount purchase row (C-10 DEBURING BLADE:
  shows ~40% Disc; edit qty 20→10 → amount 5,700, charges rescale).

---

## 7. Files touched this session
- `lib/features/queue/voucher_detail_sheet.dart` — `_recalcAmount` + 3 handler calls (sale, then
  un-gated for purchase); edit-entry `discount_pct` seeding; display + `_computeCharges` discount
  derivation; web column-width constants; `_kItemColWideW`; `_centerOnWide` + `_kSheetContentMaxW`;
  `kIsWeb` import.
- `lib/main.dart` — `MaterialApp.builder` web textScaler 1.4; `kIsWeb` import.

(Both files were already `M` in git from prior sessions; this session added to them. No new files.)

---

## 8. Outstanding / next steps (carried + new)
- ◻ **Confirm backend purchase push** accepts items that now carry `discount_pct` + a written
  `discount_total` (§4). Amounts unchanged, so low risk — but verify one real push.
- ⬜ **Commit the working tree** — still nothing committed since `711fd3c`; large multi-session diff
  on branch `project_reorg`.
- ⬜ **Rebuild the Android APK** — auth-gate + payload fixes (prior sessions) and all of this session
  are web-only so far; the device runs a stale build. `flutter build apk --release` / `flutter run`.
- ⬜ **Client DB on `yynuuysvjeipawzfbeme`** — apply join-version `get_sale_items_for_party` /
  `get_purchase_items_for_party` + indexes (item picker silently falls back to full stock catalog
  until these exist).
- ⬜ **Backend `invoice_exists`** — must start writing `voucher_payload.invoice_exists` for the queue
  "Duplicate" flag (prior session) to show in production (0 rows have it yet).
- ◻ Optional: review other web screens for text wrap/clip under the global +40% scale (§5).
