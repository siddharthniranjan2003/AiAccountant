# Price List → Rate Screen — Session Handoff

**Date:** 2026-08-10
**Branch:** `feat/two-site-nav-split`
**Status:** Data created and verified in TESTING. Frontend is mockup-only. PDF upload blocked.

This document is written to be dropped into a fresh chat as full context. Everything
below is either verified fact or explicitly flagged as an assumption.

---

## 1. The ask

The senior asked for a **demo**: show the manufacturer's price list inside the app so
that searching a stock item on the Rate screen displays its list price, and "match
prices from invoice".

Decoded, that means three things:

1. Get the TOTEM price list PDF into Supabase as a **golden dataset** (curated,
   verified reference data).
2. On the Rate / Stock Info screen, show the **list price** for the searched item.
3. Show **where the price came from** — the source PDF and the exact page.

Explicit scope decisions made by the user during the session:

- The demo must cover **all 36 pages** of the PDF, not a hand-picked subset.
- The band shows **list price only**. Margin, "You buy" and "You sell" cells were
  designed and then **removed** at the user's request.
- The page citation sits **below the PDF download button**, on the right of the band.
- Keep it to **one table** in Supabase, not a normalised catalogue + mapping pair.

---

## 2. The core insight (this is the whole idea)

**The `rate` column on sale invoices is literally the printed list price.**
The `discount_pct` column is the trade discount off that list.

Proof, from real data:

```
Item   : HSS TAP 1-1/2" BSP PAIR TOTEM
Invoice: 24 Apr 26, MAHESHWARI ENTERPRISES, 1 PAIR @ 19,666.00, disc 46% → ₹10,619.64
PDF    : page 3, BSP 1.1/2" Standard = ₹9,833 per piece
         9,833 × 2 (a PAIR is 2 pieces) = 19,666.00   ← exact match
```

In industrial tool distribution nobody quotes absolute prices; everything is
"list minus X%". This gives us a **free correctness oracle**: for any item with sale
history we can verify our extracted price against what Tally already records. That is
what makes the dataset *golden* rather than merely typed in, and it is used throughout
the pipeline below.

Note the purchase side does **not** work this way — Forbes bills a *net* rate at 0%
discount, so only sale invoices carry list prices.

---

## 3. The source document

| | |
|---|---|
| File | `D:\Downloads\TOTEM-HPT-HSS-TAPS-Price-list-Effective-01.01.2024_Gokul-Traders.pdf` |
| Title | TOTEM HSS Taps Price List |
| Publisher | **Forbes & Company Limited** |
| Effective | **08.01.2024** (see warning below) |
| Pages | 36 total, **26 are price grids** |
| Size | 2.1 MB |
| Has text layer | Yes — `pdftotext -layout` works, no OCR needed |

### ⚠ The effective date is 08.01.2024, not 01.01.2024

The **filename** says `Effective-01.01.2024`. The **cover page** says
`EFFECTIVE 08.01.2024`. The document wins. Everything seeded uses `2024-01-08`.
Trusting the filename would have baked a wrong date into a dataset whose entire
purpose is being citable.

The user confirmed **this is the latest price list** — there is no newer revision.

### Page map

| Pages | Content |
|---|---|
| 1–2 | Cover, case study — no prices |
| **3–6** | HSS Hand / Short Machine / Long Shank taps (plain) |
| 7 | Divider |
| **8–10** | TOTEM GOLD (TiN coated) |
| **11** | High Performance Taps HSSE — 480 cells, densest page |
| **12–28** | TOTEM Silver Cut — 17 pages, EDP-coded |
| **29** | NIB / Nut taps |
| 30–36 | Thread charts, selection guides, back matter — no prices |

### What is NOT in this PDF

- **No dies.** Searched all 36 pages, zero matches for die pricing. Prod carries
  161 `ROUND DIE … TOTEM` items plus more `LH DIE` items. **A separate Forbes die
  price list is needed** before the catalogue is complete.
- **No drills, reamers or centre drills** (419 DRILL items in prod).

### ⚠ A defect in the published PDF

Page 14, table 1: the **Pitch** column for M3–M16 reads
`20, 18, 16, 14, 13, 11, 10, 9, 8`. Metric M3 does not have a pitch of 20 — those
nine values are character-for-character the **TPI column from table 3 on the same
page** (a UNC inch table). It is a copy-paste error by Forbes.

Handling: captured **as printed** and flagged in the `note` column on 18 rows. A
citable dataset must match what the page actually says, because the download button
shows the reader that same page. Prices on that page appear unaffected — only the
pitch column is corrupt.

---

## 4. The frontend design (mockup only — no Flutter code written)

### Where it goes

A new full-width band in `lib/features/stock/stock_info_screen.dart`, sitting
**between the search bar and the `Name:` line**. Nothing below it changes — the
Purchase and Sale tables keep their existing six columns.

### What it shows

```
┌────────────────────────────────────────┬──────────────────────────┐
│ LIST PRICE · PER PAIR                  │  ⤓  Price list PDF       │
│ ₹19,666.00                             │     TOTEM HPT · 2.1 MB   │
│ [✓ TOTEM · eff. 08 Jan 24]             │  ▤ Refer page 3          │
└────────────────────────────────────────┴──────────────────────────┘
```

- **Left:** list price, unit, and a chip with brand + effective date.
- **Right:** download button for the source PDF, with the page citation directly
  beneath it.

### Variants and states in the mockup

| | |
|---|---|
| **A — Ledger band** | Recommended. ~62px tall, matches the table grammar already on screen. |
| **B — Single dense line** | ~34px. Cheapest vertically, loses label/value hierarchy. |
| State: matched | As drawn above. |
| State: not in price list | Band stays quiet, shows "Not in price list" and a *Link to a price list item* action. No download button — nothing to cite. |
| Phone width | PDF action drops to its own full-width row under the price. |

### Where the mockup lives

- Claude Design project: **AI Accountant — Web Theme (BG + Font)**
  `c32402c4-2e2b-44e4-b0a5-dbe15cd60ae6`
- File: `option-c-stock-info-pricelist-band.html`, card group *Option C — full app*
- Local source: `<scratchpad>/ds/option-c-stock-info-pricelist-band.html`

**Gotcha:** the Design System sidebar builds its list from `_ds_manifest.json`, which
is only regenerated by the app's own self-check. After uploading a new file you must
also add its card entry to that manifest or it uploads successfully but stays
invisible.

### Removed at user's request

Margin, "You buy" and "You sell" cells were built, then cut. Consequence: the band now
stores and displays **no derived business figures** — only transcribed facts and one
multiplication (`price_per_piece × pack_qty`). Good place for a golden dataset to be.

---

## 5. The SQL that was applied

Run by the user in the Supabase SQL Editor on the **testing** project.

```sql
create table public.price_list (
  stock_item_name  text          primary key,   -- exact Tally name

  list_rate        numeric(12,2) not null,      -- what the band shows
  unit             text,                        -- PAIR / NOS

  -- where it came from
  brand            text          not null default 'TOTEM',
  doc_title        text          not null,
  effective_from   date          not null,
  storage_path     text,
  page_no          integer       not null,

  -- how list_rate was arrived at
  price_per_piece  numeric(12,2) not null,
  pack_qty         numeric(6,2)  not null default 1,

  -- so a human can check the row is the right cell
  thread_form      text,
  size             text,
  grade            text,
  edp_code         text,

  confidence       text          not null default 'review',
  note             text,
  updated_at       timestamptz   not null default now()
);

alter table public.price_list enable row level security;
create policy "read price list" on public.price_list
  for select to anon, authenticated using (true);

insert into storage.buckets (id, name, public)
values ('price-lists', 'price-lists', true);
```

### Why each column exists

| Column | Purpose |
|---|---|
| `stock_item_name` | Primary key and the app's only lookup. One `.eq()` — no joins. |
| `list_rate` | The number the band renders, already in the invoice's unit. |
| `page_no` | The "Refer page 3" citation. |
| `storage_path` | The download button target. |
| `effective_from` | The `eff. 08 Jan 24` chip. |
| `price_per_piece` + `pack_qty` | Makes ₹19,666 explainable instead of magic. |
| `thread_form` / `size` / `grade` | Lets a human open the page and confirm the right cell. |
| `confidence` | `verified` = invoice oracle confirmed; `review` = not proven. Defaults to `review` so nothing is trusted by default. |
| `note` | Anomalies: the +10% SKUs, the LH +35% rule, the p14 PDF defect. |

**Design note:** an earlier proposal used two tables (catalogue + mapping) plus a view,
because three Tally names (`BOT`, `TPR`, `PAIR`) share one catalogue cell. The user
chose one table. That is fine here: rows are machine-generated by the extractor, not
hand-edited, so a price revision means re-running the seed, which rewrites all three
duplicated rows together.

---

## 6. The pipeline

**Committed to the repo at [`tools/price_list/`](tools/price_list/)** — see
[`tools/price_list/README.md`](tools/price_list/README.md) for run instructions.

| Script | What it does |
|---|---|
| `_cfg.py` | Resolves Supabase endpoints/keys from `.env` and `env/deployment.json` at run time |
| `phase0.py` | Smoke test — page 3/8 prices vs real invoice rates |
| `pagemap.py` | Classifies all 36 pages: price grid / chart / matter |
| `headers.py` | Dumps every grid's header block so columns can be spec'd |
| `showpage.py` | Prints any page's extracted text (debugging) |
| `tables.py` | Reports how many tables per positional page |
| `blocks.py` | Counts EDP table blocks and grades per Silver Cut page |
| `extract2.py` | **The extractor.** → `price_list_items.csv` (3,229 rows) |
| `qa2.py` | **The QA gate.** Cross-checks extract vs invoice-verified cells |
| `items.py` / `names.py` | TOTEM item name reconnaissance |
| `match.py` | Matches Tally names → catalogue cells → `price_list_rows.csv` |
| `seed.py` | Seeds `price_list` in testing |
| `crosscheck.py` | Compares seeded names against the host project's `stock_items` |
| `prune.py` | Deletes orphaned rows |
| `ratios.py` | Groups invoice-vs-list disagreements looking for a systematic rule |
| `upload.py` | PDF → Storage (**blocked, never ran**) |

Committed data files: `pages.txt` (the `pdftotext` output, so the pipeline runs
without the source PDF), `price_list_items.csv` (3,229 catalogue cells) and
`price_list_rows.csv` (all 850 matched items — a superset of the 743 seeded).

### Credentials

No keys are committed. `_cfg.py` reads them at run time from the two gitignored env
files: `.env` gives the **testing** service key (read/write) and
`env/deployment.json` gives the **production** publishable key (read only). Item
names and invoice history come from prod; rows are written only to testing.

### Order to re-run

```
cd tools/price_list
pdftotext -layout <pdf> pages.txt   # only for a new PDF revision
py extract2.py     # → price_list_items.csv   (3,229 catalogue cells)
py qa2.py          # must print "ALL MATCH" — this is the gate
py match.py        # → price_list_rows.csv    (850 matched items)
py seed.py         # upsert into price_list
py prune.py        # drop rows with no stock_items counterpart
```

### How the extractor works

Two parsers, because the PDF has two grid styles:

- **Positional** (pages 3–6, 8–11) — "Each ₹" grids. Column count is inferred from
  the count of trailing numeric/dash tokens; a spec keyed by `(page, ncols)` maps each
  column index to `(thread_form, grade)`.
- **EDP-anchored** (pages 12–28) — Silver Cut grids of `EDP Code | Price ₹` pairs.
  Walks tokens left-to-right; each `FAB…` code followed by a number emits a cell, and
  a fresh size label resets the column counter. This handles stacked *and* side-by-side
  tables in one pass.

### How `pack_qty` is decided

**Not** by naming rules. For every item with sale history the matcher divides the
actual invoice rate by the catalogue per-piece price; if the result lands on a clean
small integer (1–4), that integer becomes `pack_qty` and the row is marked `verified`.
`PAIR = 2` was *confirmed* this way across hundreds of items rather than assumed.

---

## 7. Current state

### Testing project — `price_list`

| | |
|---|---|
| Rows | **743** |
| `confidence = verified` | **401** |
| `confidence = review` | **342** |
| Catalogue behind it | 3,229 cells across 25 pages |
| Pages contributing | p3 (317), p4 (319), p5 (141), p9 (63), p6 (7), p8 (3) |

### The flagship row

```
stock_item_name : HSS TAP 1-1/2" BSP PAIR TOTEM
list_rate       : 19666.00
unit            : PAIR
price_per_piece : 9833.00
pack_qty        : 2.00
page_no         : 3
thread_form     : BSP
size            : 1.1/2"
grade           : Standard
effective_from  : 2024-01-08
confidence      : verified
storage_path    : price-lists/totem-hpt-2024-01-08.pdf
```

---

## 8. Verification evidence

**Phase 0 smoke test** — every TOTEM BSP/BSPT tap with sale history, page 3 + page 8
prices vs actual invoice rates:

```
719 sale lines · 44 distinct items
MATCH     42   (95.5%)
MISMATCH   2   (both exactly +10%, see anomalies)
NO CELL    0
```

**Extractor QA** — automated extract vs the 64 cells Phase 0 had already validated
against real invoices:

```
checked 64 invoice-verified cells → ALL MATCH
price range 390 .. 167,718        (no junk values)
rows priced under 100: 0
```

**Match stage** — of 850 matched items, 413 were confirmed by the invoice oracle
(401 after pruning orphans).

The QA harness is the durable asset here: it turns "did I read 3,000 cells correctly?"
into a test that runs in two seconds.

---

## 9. Bugs found and fixed (all caught by QA, not by eye)

1. **Size collision on page 3.** Page 3 has a 9-column inch table *and* two small
   BA/screw-number tables keyed 0–12. Stripping the inch mark made `3"` and `#3` both
   become `3`, so a ₹1,143 BA price silently overwrote the ₹58,444 BSP 3" tap.
   *Fix:* keep the inch mark, add `size_system`, and skip bare 1–2 digit labels in the
   inch parser.

2. **Page 6 double-parse.** The Special Pitch table's `Pitch` column (`40, 48`) was
   read as two extra price cells, producing ₹28 and ₹40 "taps".
   *Fix:* stop the positional pass at the `SPECIAL PITCH TAPS` header.

3. **Stacked / side-by-side tables.** The original parser assumed one table per page.
   Pages carry up to three stacked grids (p14) and two side-by-side (p23, p26),
   costing 103 cells.
   *Fix:* block-aware parsing driven by each table's own header.

4. **My own hand-typed reference was wrong.** I had transcribed page 8 BSPT `3.1/2"`
   as ₹160,257; it is ₹127,932 (₹160,257 is the 4" row). The extractor was right.

---

## 10. Anomalies and open questions

### The +10% SKUs — needs a human answer

```
HSS TAP 1/2" BSPT BOT TOTEM   list 3,057 → invoiced 3,363   +10.0%
HSS TAP 3/4" BSPT BOT TOTEM   list 4,528 → invoiced 4,981   +10.0%
```

Exactly +10% on both, stable across two customers and two dates (so not a typo). It is
**not** a BSPT-bottoming surcharge — the other four BSPT BOT sizes match list exactly.
None of the PDF's published surcharges is 10% (BSW/BSF 7.5%, nitriding 3.5%, left-hand
35%, American standards 7.5%). **Someone in the business will know this instantly.**

### 143 invoice disagreements

Of the items with sale history, 143 have invoice rates that disagree with list. Ratios
scatter from ×0.47 to ×2.2 with no systematic rule, so they were **not** bulk-corrected
— each is flagged in `note` and left at `confidence = review`. Some may indicate a
wrong cell match rather than unusual pricing; that is what review is for.

### Left-hand taps use a computed price

90 `LH` items are priced at **list × 1.35**, per the PDF's own note 4 on page 27. This
is a *computed* price, not one printed in a grid. All such rows carry the rule in
`note` and stay `review`.

### Pages 10–28 contributed nothing

Silver Cut and HSSE coated taps are extracted into the catalogue CSV but **no Tally
item name matched them**. Those Tally names don't reference SA/SB/SC grade codes in any
form the matcher recognises. Either the shop doesn't stock them, or the naming needs a
different matching strategy.

### Page 29 (NIB taps) not parsed

Different layout again — EDP code + description + physical dimensions, not a price
grid. ~30 cells, skipped.

---

## 11. Blocked / not done

### ⛔ PDF not uploaded to Storage

Uploading the PDF to Supabase Storage was **blocked by the Claude Code permission
classifier**, attempted twice (Python and PowerShell). Not retried further.

Every seeded row already has
`storage_path = price-lists/totem-hpt-2024-01-08.pdf`, so **the moment that file
exists at that path the download button works with no data change.** Either drag it
into Storage via the dashboard, or add a Bash permission rule.

Consider also whether the button should *download* the PDF or *open it at the cited
page* — the latter is just a `#page=3` URL fragment and is a much better experience.

### ⛔ No Flutter code written

`stock_info_screen.dart` is untouched. The band exists only as an HTML mockup. Wiring
it up means: query `price_list` by `stock_item_name`, render the band above the
`Name:` line, and handle the no-match state.

### ⚠ Prod is not seeded

See the environment warning below.

---

## 12. ⚠ The testing/prod split — read this before continuing

**Item names were read from PROD. Rows were written to TESTING.**

This was not a choice — the invoice oracle needs real sale history, which only exists
in prod; and the only service key available is for testing.

| | Prod `ztugwhevemibdrzqafyw` | Testing `yynuuysvjeipawzfbeme` |
|---|---|---|
| `stock_items` | 17,302 | 13,253 |
| Access | anon/publishable key — **read only** | service key in `.env` — **full RW** |

The two catalogues differ by ~4,000 items. Of the 850 matched rows, **107 referenced
items that don't exist in testing** (e.g. `CARBON TAP 3 X .5 SET TOTEM`). Those were
**deleted** — hence 743 rows.

`price_list_rows.csv` still holds all **850**. If the demo runs against prod, seed from
that CSV; a prod service key is required and is not currently available.

**Decide before demo day: does the demo run on testing or prod?** The screenshots
shared during this session came from the prod-backed deployment web app
(`https://tallybridge-deployment-env.web.app`).

---

## 13. Environment reference

```
TESTING     https://yynuuysvjeipawzfbeme.supabase.co    service key in .env (RW)
PROD        https://ztugwhevemibdrzqafyw.supabase.co    anon key in env/deployment.json (RO)

Web builds  flutter build web --dart-define-from-file=env/deployment.json
            firebase deploy --only hosting --project deployment --account deployment.riplara@gmail.com
            → https://tallybridge-deployment-env.web.app

Firebase hosting targets (.firebaserc): ops / rate / full per project
Design project: c32402c4-2e2b-44e4-b0a5-dbe15cd60ae6
Tooling: pdftotext at C:\poppler\poppler-25.12.0\Library\bin\, python via `py`
```

`.env` is gitignored and untracked — the service key is not in git history.

---

## 14. Unrelated open bugs found in `stock_info_screen.dart`

Discovered while investigating; **neither is fixed**.

1. **Nondeterministic row selection.** `.order('vouchers(date)')` has no tiebreaker, so
   when more than five rows share a date, which ones appear in the five-row window
   varies between identical requests. Observed live: the 5th sale row for
   `DRILL CHUCK 1/2" ADITECH` differed between a screenshot and a direct query.
   *Fix:* add a stable secondary sort, e.g. `.order('id')`.

2. **"5 entries" is not the entry count.** It is `rows.length` after `.limit(5)`. The
   real totals for that item were 10 purchase and 108 sale lines.

---

## 15. Suggested next steps

1. Upload the PDF to the `price-lists` bucket (unblocks the download button).
2. Wire the band into `stock_info_screen.dart` — query, render, no-match state.
3. Get a human answer on the +10% SKUs; record it in `note`.
4. Decide testing vs prod for the demo; if prod, obtain a service key and seed from
   `tools/price_list/price_list_rows.csv` (all 850 rows).
5. Obtain the Forbes **die** price list if dies need to be covered.
6. Optionally fix the two `stock_info_screen.dart` bugs in §14.
