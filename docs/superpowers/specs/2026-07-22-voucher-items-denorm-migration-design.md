# Sourcing `date` / `party_name` / `voucher_type` from `vouchers` instead of `voucher_items`

**Date:** 2026-07-22
**Status:** Approved, ready for implementation planning
**Scope:** Code only. No database changes.

## Problem

`public.voucher_items` carries three denormalized columns — `date`, `party_name`,
`voucher_type` — that duplicate `vouchers.date` / `vouchers.party_name` /
`vouchers.voucher_type` across the `voucher_id` foreign key.

They are not maintained consistently, and one consumer still reads them. That
consumer shows users the wrong data today.

### This is a live production bug, not cleanup

The app's production project is `yynuuysvjeipawzfbeme` (`lib/core/config.dart:16`,
`env/prod.json`, `env/testing.json`). The `deployment` flavor points at a
different project, `ztugwhevemibdrzqafyw`, and the two behave in opposite ways:

| | `yynuu…` (prod, testing) | `ztugw…` (deployment) |
|---|---|---|
| `voucher_items.date` / `party_name` | backfilled once, **no maintaining trigger** | kept in sync by a `BEFORE INSERT` trigger |
| `voucher_items.voucher_type` | backfilled once, then NULL | **100% NULL** (trigger never sets it) |
| Newest rows | **NULL** on all three | populated (except `voucher_type`) |

On production, every `voucher_items` row inserted since **2026-07-20 08:47 UTC**
has NULL `date` / `party_name` / `voucher_type` while its parent voucher holds
the real values. 19 rows at time of writing, growing with every Tally sync.

Because Stock Info sorts with `.order('date', desc).limit(5)`, those NULL-dated
rows sort last and **never appear**. Verified against production for
`C-10 DEBURING BLADE`:

```
current query  → latest sale 2026-06-16   ← wrong; omits the newest invoice
migrated query → latest sale 2026-07-20   ← correct
```

That is the figure users read off the screen to set prices.

### Provenance

Neither the three columns nor the `ztugw` trigger (`trg_fill_voucher_item_meta`
→ `tb_fill_voucher_item_meta()`) exist in any `.sql` file in either repo. They
were added out of band. `TallyBridge/backend/full_schema.sql:93-103` declares
only the original nine columns — the tracked schema is *already* the
post-migration shape; the live databases are what drifted.

Commit `59cf60f` (2026-07-20, "wire Stock Info window to live data") introduced
this dependency as an optimization, three weeks after `e72563a` (2026-07-08)
moved the queue picker off it for the same underlying reason.

## Dependency map

Swept both repos exhaustively; every candidate hit was adversarially verified.

| Repo | Queries reading the three columns off `voucher_items` |
|---|---|
| AiAccountant (Flutter) | **2, both in `lib/features/stock/stock_info_screen.dart`** |
| TallyBridge (TS / JS / Python / SQL / n8n) | **0** |

The app issues exactly five queries against `voucher_items`. Three
(`voucher_detail_sheet.dart:3220`, `:3311`, `:3375`) already source these values
through the parent voucher. Two (`stock_info_screen.dart:133`, `:150`) do not.

TallyBridge touches `voucher_items` only through `select("*")` wildcard
round-trips (`backend/src/routes/sync.ts:733` → `:791` → `:804`, and `:2017` →
`:2107`). These are schema-agnostic and need no edits. No application code in
either repo *writes* these columns — the Tally XML parser
(`src/python/xml_parser.py:348-355`) emits only
`stock_item_name, quantity, unit, rate, discount_pct, amount`, and the ingest
RPC inserts only those seven columns.

### The pattern to copy

`lib/features/queue/voucher_detail_sheet.dart:3219-3238` is the canonical
already-migrated form, and its own comment at `:3201-3207` records why it moved:
the `get_{sale,purchase}_items_for_party` RPCs were abandoned because they
matched on `voucher_items.party_name`, "which the sync leaves null."

## Design

One file, five edits, no database changes.

### `lib/features/stock/stock_info_screen.dart`

| Line | Now | Becomes |
|---|---|---|
| `83-85` | `'… amount, date, party_name, vouchers!inner(voucher_type)'` | `'… amount, ...vouchers!inner(date, party_name, voucher_type)'` |
| `137` | `.order('date', ascending: false)` | `.order('vouchers(date)', ascending: false).order('id', ascending: true)` |
| `156` | `.eq('party_name', _party)` | `.eq('vouchers.party_name', _party)` |
| `158` | `.order('date', ascending: false)` | same as `137` |
| `31-34`, `79-82` | comments asserting the values are "read straight off the line" | rewritten — they document the opposite of the new design |

The resulting select constant:

```dart
static const _select =
    'stock_item_name, quantity, rate, unit, discount_pct, amount, '
    '...vouchers!inner(date, party_name, voucher_type)';
```

**`_Txn.fromRow` (`:43`, `:45`) does not change.** The `...` spread operator
flattens a to-one embed into top-level response keys, so `row['date']` and
`row['party_name']` keep working and the entire widget tree below is untouched.
That is what keeps this change small.

### Design decisions

**Use the spread form, not a nested embed.** A nested
`vouchers!inner(date, …)` would return `{"vouchers": {"date": …}}` and force
changes in `_Txn.fromRow` and every consumer of it. The spread keeps the
response shape byte-identical to today's.

**Keep `!inner`.** It is load-bearing twice over: it applies the `voucher_type`
filter *and* the `party_name` filter. Verified on production — dropping it
returns HTTP 200 and silently stops filtering (102,816 rows instead of 1,325),
which would show other customers' sales under a chip that still reads as scoped.

**Add `.order('id', ascending: true)` as a tiebreak.** Many lines share a date;
without a deterministic second sort key, which five rows survive `.limit(5)` is
unstable, and `latest: i == 0` (`:262`) badges row 0 as "latest". Adjacent pages
currently duplicate ids — pre-existing, closed here.

**Never `.order(…, referencedTable: 'vouchers')`.** `postgrest-2.7.0`
(`postgrest_transform_builder.dart:83`) emits `vouchers.order=…` for that form,
which sorts *within* the embed and leaves the top level unsorted — HTTP 200,
wrong data. The string form `.order('vouchers(date)')` is the working one. No
uses exist in the repo today.

### Verified on production

The exact query string `postgrest-dart 2.7.0` will emit —
`order=vouchers(date).desc.nullslast,id.asc.nullslast` — returns HTTP 200 with
flat top-level keys, correctly sorted newest-first, party-scoping intact.
The client's unconditional `.nullslast` suffix is accepted alongside the
`vouchers(col)` form, and chained `.order()` calls comma-append correctly.

## Risks

| Risk | Assessment |
|---|---|
| Row counts change | No. `!inner` is already in the current query, so any orphan lines are dropped today too — and there are none (`0` orphans measured). |
| Null handling | Strictly improves. This is the bug being fixed. |
| Result ordering | Improves (correct rows surface) and becomes deterministic (id tiebreak). |
| Latency | ~1.4–1.9× slower (0.29s → 0.47s measured): the sort can no longer use an index on `voucher_items`. Acceptable for a 5-row panel. |
| Silent failure | **The main hazard.** Both failure modes return HTTP 200, and `catch (_)` at `:141` / `:161` swallows everything into a generic string. Manual verification is mandatory. |

## Verification

Automated tests cannot catch the failure modes here — they are live-data,
HTTP-200-with-wrong-rows problems. Verification is manual, against production:

1. **Regression case:** open Stock Info for `C-10 DEBURING BLADE`. Before the
   change the Sale panel's newest row is `2026-06-16`; after, it must be
   `2026-07-20`. This single check proves the bug is fixed.
2. **Party scoping:** open Stock Info from a sale invoice with a customer. The
   Sale panel must show only that customer's lines. Toggle the chip off — the
   panel widens to all customers. This guards the missing-`!inner` trap.
3. **Latest badge:** confirm the badge sits on row 1 of each panel.
4. **Headline:** confirm "Last purchased on … @ ₹…" (`:742-743`) names the same
   date as the top row.
5. **Purchase panel:** confirm it still loads and sorts newest-first (it has no
   party filter, so it exercises the order change in isolation).
6. `flutter analyze` must be clean.

## Explicitly out of scope

- **Dropping the columns.** Deferred by decision. Once nothing reads them they
  cost only storage. A future `DROP COLUMN` must drop `trg_fill_voucher_item_meta`
  and `tb_fill_voucher_item_meta()` in the *same transaction* on `ztugw…`, or
  every `voucher_items` INSERT errors and the Tally sync goes down.
- **Auditing production's function bodies / indexes.** Requires service-role
  access to `yynuu…`, which is not available. Not needed for a code-only change;
  it becomes a blocker only if a `DROP` is attempted.
- **`backend/full_schema.sql` drift** and the stale `backend/src/routes/sync.js`
  build artifact. Both are real, both are pre-existing, neither is touched here.
