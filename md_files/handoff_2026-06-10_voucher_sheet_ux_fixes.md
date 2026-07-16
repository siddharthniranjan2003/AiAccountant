# AI Accountant — Dev Handout (session 2026-06-10, voucher-sheet UX fixes)

Context handoff for a fresh chat. Covers everything done **this session**. All changes are
**uncommitted** working-tree state (nothing committed since `711fd3c`). Three fixes shipped,
each built + deployed to Firebase Hosting (web). All live on **https://aiaccountant-b60ed.web.app**.

> Companion doc: `handoff_2026-06-08_pickers_editing_config.md` covers the two-Supabase-project
> setup, the item-picker RPCs, config centralization, and the still-open DB task on the client
> project. **Still outstanding from that doc:** apply the join-version `get_sale_items_for_party`
> / `get_purchase_items_for_party` + indexes on the CLIENT project `ztugwhevemibdrzqafyw`.

---

## 0. Build / deploy basics (unchanged)
- Web: `flutter build web --release` → `firebase deploy --only hosting --project aiaccountant-b60ed`.
- Live URL: **https://aiaccountant-b60ed.web.app**.
- **Service-worker cache caveat (bit us repeatedly):** after every deploy you MUST hard-refresh
  (Ctrl+Shift+R twice) or DevTools → Application → unregister SW + clear site data, or you keep
  seeing the old bundle and think the fix didn't ship.
- A deploy session also hit a **transient network outage** (even `google.com` timed out) and an
  expired Firebase token (`firebase login --reauth`, interactive). Not code issues.

## 1. All changes are in two files
- `lib/features/queue/voucher_detail_sheet.dart` (the big voucher detail bottom sheet)
- `lib/features/auth/success_screen.dart` (one-line nav fix)

No other files changed this session. `flutter analyze` clean throughout.

---

## 2. Fix #1 — typing into Qty/Disc/Rate/Amount dropped focus after one digit
**Symptom (web + mobile):** in an editable item row, after typing/editing **one digit** the
numeric field closed; you had to click again for each digit.

**Root cause:** the Disc/Rate/Amount cells were keyed on their own value
(`key: ValueKey('amount_$amount')` …). Each keystroke → `onChanged` → `_recomputeChargesFromItems()`
→ `setState` → rebuild; the value changed so the `ValueKey` changed → Flutter destroyed &
recreated the `TextFormField` → focus lost. (Qty had no key, so it was unaffected — the tell.)
Those keys existed so a **stock-item pick** (which rewrites rate/amount via setState) refreshed
the field instead of showing stale text.

**Fix:** converted `_EditableNumCell` from a `StatelessWidget` (uncontrolled `initialValue`) to a
**`StatefulWidget` with its own `TextEditingController`**, and added `didUpdateWidget` that rewrites
the text **only when the value changed from OUTSIDE** (i.e. `widget.initial != old.initial` AND it
doesn't already match what the user just typed). Removed the three value-based `ValueKey`s. This
keeps focus while typing AND still refreshes on a stock-item pick.

## 3. Fix #2 — "auth not persisting": back button returned to Login
**Symptom:** after signing in, pressing back (Android hardware / browser) landed on the Login page.
Reported as "authentication not persisting" — but the Firebase session WAS persisting; it was a
**navigation-stack** bug.

**Root cause:** `SplashScreen` does `pushReplacement(Login)` which removes the root `/` route (the
`StreamBuilder(authStateChanges)` auth gate in `main.dart`). Then OTP → `pushReplacement(Success)`
→ Success → `pushReplacement(AccountantShell)`. Final stack = `[Login, Shell]`, so back popped the
Shell and revealed Login.

**Fix (`success_screen.dart`):** changed `pushReplacement` → `pushAndRemoveUntil(..., (route) => false)`
when entering the Shell, so the Shell becomes the only route. Covers both the manual-OTP path and
Login's auto-verification path (both funnel through Success). Web-refresh persistence still works
independently via the `StreamBuilder` gate in `main.dart` (a refresh rebuilds the navigator fresh).

## 4. Fix #3 — TallyPrime-style Enter-to-advance across numeric cells
**Want:** while editing (sale + purchase), pressing **Enter** moves focus through the numeric
cells only — Qty → Disc → Rate → Amount → next row's Qty → … → and in Charges: GST Sale → CGST →
SGST → … → Discount → Total. Item-name dropdown and delete must NOT be focused by Enter.

This took three iterations; the **final, correct** state is:

1. **Deterministic order, not geometry.** Wrapped the summary `ListView` (in `_buildSummaryView`)
   in `FocusTraversalGroup(policy: OrderedTraversalPolicy())`. Assigned each editable field an
   explicit `FocusTraversalOrder(order: NumericFocusOrder(n))`:
   - `_SheetItemRow` gained an `int orderBase` param; the loop passes `orderBase: i * 4`; inside the
     row the four cells are wrapped with order `orderBase + 0/1/2/3` (Qty/Disc/Rate/Amount).
   - Charges (in `_buildSummaryView`): `final chargesOrderBase = displayItems.length * 4;` then
     `breakdownEntries.indexed` → order `chargesOrderBase + ci`; Discount → `+ breakdownEntries.length`;
     Total → `+ length + 1`. So the chain continues straight from the last Amount into GST Sale.
   - The item-name & delete cells are `GestureDetector`s (not focusable) → skipped for free.
2. **Enter handler on both editable widgets:** `_EditableNumCell` (items) and `_SheetEditableRow`
   (charges) each got `onFieldSubmitted: (_) => FocusScope.of(context).nextFocus()` +
   `textInputAction: TextInputAction.next`.
3. **THE bug that made it skip every other field:** a `TextField` with `textInputAction.next`
   **already advances focus on Enter by itself**; combined with our `onFieldSubmitted` nextFocus it
   advanced **twice** per Enter (Qty→Rate skipping Disc, etc.). **Final fix: added
   `onEditingComplete: () {}` to both widgets** to suppress the built-in advance, leaving exactly
   one `nextFocus()` per Enter. (If you ever change these fields, keep the `onEditingComplete: () {}`
   guard or the double-jump returns.)
4. **Bonus already in `_EditableNumCell`:** a `FocusNode` listener selects the whole value on focus
   (Enter-advance or click) so you can immediately type over it, Tally-style.

**Known/intended edge:** after the last item row's Amount, Enter continues into the first Charges
field (GST Sale) — by design (one continuous downward chain). After Total, nextFocus moves to
whatever is next (header text fields land at the end of the ordered group; they don't advance on
Enter anyway).

---

## 5. Quick reference — key widgets in `voucher_detail_sheet.dart`
- `_EditableNumCell` — stateful numeric cell for Qty/Disc/Rate/Amount. Owns controller + focusNode
  (+ select-all-on-focus), `didUpdateWidget` external-refresh logic, `onEditingComplete:(){}` +
  `onFieldSubmitted: nextFocus`. **No `key` param anymore.**
- `_SheetEditableRow` — stateless numeric Charges row (ledger/discount/total). Uses `initialValue`;
  has `onEditingComplete:(){}` + `onFieldSubmitted: nextFocus`. (Still re-keyed by value via
  `ValueKey` in `_buildSummaryView` so recompute refreshes it — that's fine; it has no controller.)
- `_SheetItemRow` — one item row; new `orderBase` field; wraps its 4 cells in `FocusTraversalOrder`.
- `_buildSummaryView` — wraps the `ListView` in `FocusTraversalGroup(OrderedTraversalPolicy())`,
  computes `chargesOrderBase`, orders the charges fields.
- Edit/Add/Save/Revert/Push lifecycle is unchanged this session (see `_toggleEdit`, `_addItem`,
  `_revert`, `_persistEditsToSupabase`, `_activate`; push always overrides `narration='Replara AI'`).

## 6. Outstanding / next steps
- ⬜ **Commit the working tree** — nothing committed since `711fd3c`; this session's two files plus
  everything from the 2026-06-08 session are uncommitted.
- ⬜ **Client DB task (from prior handout):** apply join-version `get_sale_items_for_party` /
  `get_purchase_items_for_party` + indexes on `ztugwhevemibdrzqafyw`.
- ⬜ **Verify Fix #3 on a hard-refreshed web build** (the cache repeatedly masked deploys).
- The same Dart fixes apply to **mobile**, but need an Android rebuild (`flutter build apk` /
  `flutter run`) to land on a device — only web was rebuilt/deployed this session.

## 7. Verify quickly
1. `flutter analyze lib/features/queue/voucher_detail_sheet.dart` → clean.
2. Web, after hard-refresh: open a sale (and purchase) voucher → Edit → click a row's Qty, type,
   press Enter → focus steps Qty→Disc→Rate→Amount→next row's Qty→…→GST Sale→CGST→…→Total, one field
   per press, value pre-selected; item-name never focused by Enter.
3. Typing multiple digits into Amount/Rate/Disc keeps focus (no re-tap needed).
4. Log in → land on queue → press back → stays in app / exits (does NOT return to Login).
