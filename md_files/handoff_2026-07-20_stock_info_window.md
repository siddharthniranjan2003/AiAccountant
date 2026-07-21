# Handoff — Stock Info Window (Purchase/Sale history + search + customer filter)

**Date:** 2026-07-20
**Branch:** `feature/stockInfo` (off `feature/scan-loading-timer-loop`) — commit `59cf60f`, pushed to `origin/feature/stockInfo`.
**Scope:** A standalone "Stock Info" page that shows an item's recent Purchase & Sale history, opened from the ⓘ icon on voucher item rows. Wired to live Supabase data, with type-ahead search and a customer filter chip.

This doc is meant to onboard a fresh chat: read it top-to-bottom and you'll understand what exists, why it's built this way, the data model, the gotchas, and what's left.

---

## 1. What the feature is

- Every item row in the voucher-detail sheet has a small **ⓘ** button. Clicking it opens a **new browser tab** at `#/stock-info?item=<name>&party=<name>`.
- That tab renders `StockInfoScreen` — a two-panel page:
  - **PURCHASE** (left): the item's last 5 purchases (item-scoped, any vendor).
  - **SALE** (right): last 5 sales. When opened from a **sale** invoice, it's scoped to that invoice's **customer + this item**; a chip lets you toggle/remove that scope.
- A top **search bar** lets you type to find any stock item and load its panels without reopening the tab.

The page deliberately opens as a **fresh app instance in a new tab** (no shared in-memory state) and **bypasses the auth gate** — it reads Supabase directly with the anon key.

---

## 2. Files (the whole surface area)

| File | Role |
|---|---|
| `lib/features/stock/stock_info_screen.dart` | **The screen** — queries, both panels, search widget, customer chip, formatting. ~700 lines; the bulk of the feature. |
| `lib/services/stock_info_launcher.dart` | `StockInfoLauncher.open({itemName, partyName})` — builds `#/stock-info?item=…&party=…` and opens a new tab via `url_launcher` (`webOnlyWindowName: '_blank'`). Party is only appended for a real value. |
| `lib/features/queue/voucher_detail_sheet.dart` | The **ⓘ button** (`_infoIconButton`) + its two call sites in `_SheetItemRow`. Passes `itemName` always and `partyName` **only when `isSale`** (`partyName: isSale ? partyName : null`). Also: the "New Item" column was removed from the Sale items table this session (see §8). |
| `lib/main.dart` | Route parsing (~line 99): `route.path == '/stock-info'` → `StockInfoScreen(itemName: qp['item'], partyName: qp['party'])`, instead of `AuthGate`. `Supabase.initialize` runs unconditionally in `main()`, so the anon client is ready on this route even with no Firebase session. |
| `lib/core/utils.dart` | `formatShortDate(iso)` → `"29 May 26"`; `formatDecimal(n)` → Indian-grouped 2dp `"2,011.00"` (no ₹). `formatCurrency` (pre-existing) is `₹` + Indian grouping. |
| `pubspec.yaml` / `pubspec.lock` | `url_launcher` promoted to a **direct** dependency (the launcher needs it). |

---

## 3. Supabase data model — READ THIS (it's the source of every subtlety)

There are **two projects**. Same schema shape, different data-population reality:

| Env file | Project ref | Notes |
|---|---|---|
| `env/deployment.json`, `env/prod.json` | `ztugwhevemibdrzqafyw` ("client"/prod) | `voucher_items.date` & `party_name` are **100% populated** and match the parent voucher. |
| `env/testing.json` | `yynuuysvjeipawzfbeme` ("testing") | `voucher_items.date`/`party_name`/`voucher_type` are **partially NULL** (newer synced rows are NULL, older ones populated) → shows `—` until backfilled. |

**`voucher_items` columns:** `id`, `voucher_id` (FK → `vouchers.id`), `stock_item_name`, `quantity`, `unit`, `rate`, `discount_pct`, `amount`, `created_at`, `date`, `party_name`, `voucher_type`.

Hard facts established by direct queries:
- **`voucher_items.voucher_type` is NULL everywhere** (0 populated on both projects). The reliable `voucher_type` lives on **`vouchers`**. → Always resolve purchase/sale through the join `vouchers!inner(voucher_type)`.
- **`voucher_items.amount` is SIGNED**: purchases stored **negative**, sales **positive**. Always display `amount.abs()`.
- **`vouchers`** (source of truth): `date` ~100%, `party_name` ~99% (the ~1% NULLs are party-less accounting vouchers — Journal/Contra/Receipt/Payment), `voucher_type` 100%.
- **RLS is DISABLED** on `voucher_items`, `vouchers`, `stock_items` → the anon key reads everything. (This is how the standalone tab works, and how you can query via REST — see §9.)
- **`stock_items`** (catalog, ~17k rows): `name`, `group_name`, `unit`, `rate`, `part_code`, `closing_qty`. Searchable with `ilike`. This backs the search box.

### 3a. The one big fragility
`stock_info_screen.dart` currently reads `date` and `party_name` **directly off the `voucher_items` row** (an optimization made because they were populated on the client project). That makes the page **depend on those denormalized columns being filled**. On testing they're partly NULL → dates/parties render as `—`. Two ways to deal with it: backfill the data (§9) or the **durable fix** — read `date`/`party_name` from the `vouchers` join instead (see §10, TODO).

---

## 4. Query logic (`stock_info_screen.dart`)

```dart
static const _select =
  'stock_item_name, quantity, rate, unit, discount_pct, amount, date, '
  'party_name, vouchers!inner(voucher_type)';
```

- **Purchase (always item-scoped):**
  `.eq('stock_item_name', _item).ilike('vouchers.voucher_type', '%purchase%').order('date', ascending:false).limit(5)`
- **Sale:** same with `%sale%`; when the customer filter is active, add `.eq('party_name', _party)`.
- Rows → `_Txn.fromRow`: `date`, `party_name` read top-level; `amount` shown as `'₹${formatDecimal(rawAmount.abs())}'`; qty `"N UNIT"`; disc `discount_pct` (`—` if null); LATEST badge on index 0; summary line from row 0 ("Last purchased/sold on <date> · <qty> @ ₹<rate>").

### Purchase-vs-Sale = `voucher_type`, NOT amount sign — and WHY
The user considered filtering by `amount < 0`/`> 0` (no join). **Rejected**, because credit/debit notes carry signed stock lines that a sign-only filter would misfile. **Live proof:** Credit Note `KVE/26-27/CN/21` (RAMCO STEELS, 2026-06-09) has a `−8580` line for `HSS CENTRE DRILL R 4 X 10 ADDISON`. Amount-sign would show it as that item's *latest purchase* (later than the true 2026-05-21 buy); the `voucher_type` join correctly excludes it (it's a `Credit Note`, doesn't match `%purchase%`). **Decision: keep the join.**

---

## 5. UI components

### Panels (`_HistoryPanel`, `_TxnHeaderRow`, `_TxnRow`, `_LatestBadge`)
- Columns: DATE · PARTY NAME · QTY · RATE · DISC % · AMOUNT. `showParty` hides the PARTY column when the panel is scoped to one party.
- Loading spinner while `rows == null`; per-panel empty message; per-panel error (each panel loads independently).
- When `_item` is empty (after clearing search): a centered "Search a stock item above…" hint replaces the panels.
- Wide screen = side-by-side scroll panes; narrow = stacked.

### Customer chip (`_PartyToggle`)
- Only shown on the **Sale** panel when a party was passed **and** an item is selected.
- **Tap the body** → toggles active/inactive. **× on the right** → removes it entirely.
- Three states, driven by `_partyActive` + `_partyRemoved` (→ `_hasParty`, `_partyScoped`):
  - **Active** (default): yellow tint (`accent2`@0.20), `Icons.filter_alt`, bold ink → shows *this customer's* sales of the item.
  - **Inactive** (tapped off): `card` fill, `Icons.filter_alt_off`, muted → shows **all** sales of the item (PARTY column returns).
  - **Removed** (×): chip gone, all sales, stays removed across item switches.
- **No auto-fallback** (explicit user decision): active + item never sold to this customer → shows the empty *"No sales of this item to <customer> yet."* (not all sales). Toggle off or × to see all.
- The chip state is **sticky across search item-switches**.

### Search (`_SearchBar` → `_SearchBarState`, uses `RawAutocomplete<String>`)
- `_search(value)`: min **2 chars**; **250ms debounce** via an incrementing `_token` (superseded keystrokes skip the query and return the last options); queries `from('stock_items').select('name').ilike('name','%q%').order('name').limit(20)`. **Capped at 20 results.**
- `fieldViewBuilder`: the styled TextField (search prefix + a **clear ×** suffix that resets item + both panels).
- `optionsViewBuilder`: floating `Material` list; width matched via a `LayoutBuilder`.
- **Two web-specific fixes (important — don't regress these):**
  1. The options view is wrapped in **`TextFieldTapRegion`** so tapping an option doesn't unfocus the field and dismiss the overlay before the tap lands.
  2. Each row selects via **raw pointer events** — `Listener(onPointerDown: record pos; onPointerUp: select if moved <18px)` — because Flutter-web's scrollable gesture arena was swallowing the `InkWell.onTap`. This preserves scrolling while making clicks register. (The `InkWell` is kept only for the hover highlight.)
- Selecting an item → `_selectItem(name)` reloads both panels; the chip state carries over.

### Formatting helpers
`formatShortDate` (dd MMM yy), `formatDecimal` (Indian 2dp), `formatCurrency` (₹). No `intl` dependency.

---

## 6. Behavior matrix (quick reference)

| Opened from | Party in URL? | Purchase panel | Sale panel |
|---|---|---|---|
| Sale invoice | yes (customer) | last 5 purchases of item | scoped to customer+item; chip active; toggle/remove to widen |
| Purchase invoice | no | last 5 purchases of item | last 5 sales of item (no chip) |
| Direct link / search, no party | no | item-scoped | item-scoped |

Chip: **active** → customer's sales (may be empty, no fallback); **inactive** → all sales; **removed** → all sales, chip gone.

---

## 7. Git / deployment state

- **Committed** on `feature/stockInfo` (`59cf60f`, pushed): the two new stock files, the ⓘ wiring in `voucher_detail_sheet.dart` + `main.dart`, `utils.dart` helpers, and `pubspec.yaml`/`pubspec.lock` (url_launcher direct).
- **NOT committed** (still in working tree): `firebase.json` (unrelated pre-existing change), `command.txt` (scratch), and the **"New Item" column removal** from §8 (applied but uncommitted).
- The deployed testing web app (`tallybridge-testing-env-636d4.web.app`) may lag the branch — verify which build is live before trusting deployed behavior.

---

## 8. Loose end this session — "New Item" column removed (uncommitted)

The Sale items table in `voucher_detail_sheet.dart` had a sale-only **"New Item"** column (a red "Y" flag from `rate_source == 'different_party'`). It was **removed from the UI** (header cell + row cell + the `_kNewItemColW` const + the narrow-layout width sum). The underlying `rate_source` logic and row coloring / "Needs Attention !!" were left intact. `flutter analyze` clean. **This edit is not committed yet.**

---

## 9. Testing-project data issue + fixes (the `—` dates)

**Symptom:** On testing, DATE and PARTY NAME show `—` for many rows (numbers/amounts still show). **Cause:** those `voucher_items` rows have NULL `date`/`party_name` (the sync left them; the app reads them off the line). The parent `vouchers` rows DO have the values.

**Backfill SQL** (run in the target project's SQL editor — copies voucher fields down to line items):
```sql
update public.voucher_items vi
set date         = v.date,
    party_name   = v.party_name,
    voucher_type = v.voucher_type
from public.vouchers v
where vi.voucher_id = v.id
  and (vi.date is null or vi.party_name is null or vi.voucher_type is null);
```
Pre-check the source first (all counts should be > 0): `select count(*), count(date), count(party_name), count(voucher_type) from public.vouchers;` (testing returned 45069 / 45069 / 44761 / 45069).

**Querying testing without the MCP:** the `claude.ai Supabase` MCP was flaky all session. Since RLS is off, you can hit the REST API directly with the anon key from `env/testing.json`. Use `curl` (macOS system certs) — Python's `urllib` failed SSL cert verification. Example (find items never sold to a party = empty-state test cases):
```bash
BASE="https://yynuuysvjeipawzfbeme.supabase.co/rest/v1"
KEY="<SUPABASE_ANON_KEY from env/testing.json>"   # sb_publishable_...
curl -s "$BASE/voucher_items?select=stock_item_name,vouchers!inner(party_name,voucher_type)&vouchers.party_name=eq.HARYANA%20H%2FW%20%26%20MILL%20STORE&vouchers.voucher_type=ilike.*sale*&limit=100000" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```
PostgREST caps responses (~1000 rows); check the returned count to know if you hit the cap.

---

## 10. Verification & test data

- `flutter analyze lib/features/stock/stock_info_screen.dart` → clean.
- Run: `flutter run -d chrome --dart-define-from-file=env/deployment.json` (or `env/testing.json`).
- Deep-link (bypasses auth): `#/stock-info?item=<name>&party=<name>`.
- **Testing-project (`yynuuysvjeipawzfbeme`) test data for HARYANA H/W & MILL STORE:**
  - **Never sold to HARYANA** (empty-state; each *does* have sales to others): `DIAMOND DRESSER FD106 GNL`, `HSS CENTRE DRILL BS3 TOTEM`, `HSS ENDMILL 12 MIRANDA`, `HSS TAP 20 X 2.5 SET TOTEM`, `EMERY CLOTH FINE JOHNOAKEY`.
  - **HARYANA did buy** (populated party-scoped panel): `HSS DRILL 9.4 ADDISON`, `HSS TAP 6 X 1 SPPT TOTEM`.
- Flow test: search an item → pick it → panels load; chip active shows customer's sales (or empty), tap off → all sales, × → chip gone; search-bar × → empty state.

---

## 11. Open items / TODO

1. **Durable fix for the `—` fragility (recommended):** change the queries to `vouchers!inner(date, party_name, voucher_type)` and read `date`/`party_name` from the **embed** (and filter party on `vouchers.party_name`). Then the page works on any env regardless of whether `voucher_items` is backfilled. Currently it reads those off the line item.
2. **Commit the "New Item" column removal** (§8) if keeping it.
3. **Search result cap** is 20 (`.limit(20)`); consider lowering to ~8–10 so the dropdown fits without scrolling (also reduces reliance on the pointer-tap workaround).
4. **Confirm the pointer-tap dropdown fix** end-to-end in the browser (it was the last thing being verified — hover worked; click via raw pointer should now select).
5. Consider committing/handling `firebase.json` + `command.txt` separately (they're not part of this feature).

---

## 12. Memory note

Persistent memory file `supabase-voucher-items-schema.md` captures the schema quirks (voucher_type null on the line → join vouchers; date/party denormalized-but-sometimes-null; amount signed; classify by voucher_type not amount sign; the RAMCO credit-note example). Keep it in sync if the schema handling changes.
