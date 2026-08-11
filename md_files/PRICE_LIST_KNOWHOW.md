# Price List Work — Know-How & Know-Why

A self-contained explainer for someone picking this up cold, in another chat or on
another machine. It covers **why** each decision was made and **how** the mechanisms
work. It deliberately avoids machine-specific paths.

Companion document: `PRICE_LIST_HANDOFF.md` covers *state* — what exists right now,
what is blocked, what the numbers are. This one covers *reasoning*.

---

# PART 1 — KNOW WHY

## 1.1 The trade this software serves

The business distributes industrial cutting tools (taps, dies, drills) made by brands
like TOTEM. In this trade **nobody quotes an absolute price**. The manufacturer
publishes a list price, and every transaction is expressed as *"list minus X%"*.

- A customer isn't quoted "₹10,619". They're quoted **"46% off"**.
- Two customers on different discounts are only comparable through the list price.
- A salesman's discretion *is* the discount percentage.

This single fact is why a price list belongs inside the app at all. Without it, an
invoice rate is a number with no context. With it, every rate becomes a position on a
scale everyone in the trade already thinks in.

## 1.2 The insight everything rests on

**The `rate` column on a sale invoice is literally the printed list price.**
The `discount_pct` column is the trade discount off it.

```
Invoice line : 1 PAIR @ rate 19,666.00, disc 46%  →  amount 10,619.64
Price list   : page 3, BSP 1.1/2" Standard = ₹9,833 per piece
               9,833 × 2 (a PAIR is two pieces) = 19,666.00      ← exact
```

Two consequences follow, and both shape the whole design:

**(a) We get a free correctness oracle.** For any item with sale history we can check
our extracted price against what the accounting system already recorded. Reading 3,000
numbers off a PDF is normally an act of faith; here it is testable.

**(b) Only the sale side works this way.** Purchase invoices from the supplier carry a
*net* rate at 0% discount. Never try to verify against purchases.

## 1.3 Why "golden dataset" means verified, not typed

The phrase gets used loosely. Here it has a specific operational meaning: **no row is
trusted until something independent agrees with it.**

The `confidence` column defaults to `review`. A row is promoted to `verified` only when
real invoice history confirms it. That is why the schema carries `confidence`,
`verified_by` and `note` at all — provenance of *belief*, not just provenance of data.

This paid off five times. Every parser bug listed in Part 3 was caught by the oracle,
not by reading output.

## 1.4 Why citation is the feature, not decoration

The screen shows a price, the source document, and **the exact page**. That is not
polish. In this trade a price is an argument in a negotiation — someone will
eventually say "that's not what TOTEM charges." The page citation is what ends that
conversation in ten seconds instead of ten minutes.

It also has a design consequence: **the stored data must match what the page prints.**
See 1.7.

## 1.5 Why one table (and what it costs)

The natural modelling is two tables — a catalogue of every price cell, and a mapping
from item names to cells — because three different item names can share one cell:

```
HSS TAP 1-1/2" BSP BOT  TOTEM   →  page 3, BSP 1.1/2" Standard  ×1
HSS TAP 1-1/2" BSP TPR  TOTEM   →  same cell                    ×1
HSS TAP 1-1/2" BSP PAIR TOTEM   →  same cell                    ×2
```

One table means ₹9,833 is stored three times. The stakeholder chose one table, and it
is defensible here **because rows are machine-generated, never hand-edited**. A price
revision means re-running the extractor, which rewrites all three copies together. The
drift risk that normally makes duplication dangerous doesn't apply to a generated table.

Know the tradeoff, though: the moment anyone edits a price by hand in the database,
that argument collapses.

## 1.6 Why pack size is derived, not read from the name

`PAIR` looks like it obviously means 2. It does — but *believing* the name is how you
get silently wrong data, because naming conventions in a Tally catalogue built over
years are not consistent (`SET`, `PAIR`, `BOT`, `TPR`, `SEC`, and blanks all coexist).

So pack size is **inferred from invoices** and only falls back to the name when there
is no history. `PAIR = 2` is a finding confirmed across hundreds of items, not an
assumption. See 2.5 for the algorithm.

## 1.7 Why source defects are preserved, not fixed

Page 14 of the TOTEM list has a corrupted **Pitch** column — the publisher pasted the
TPI values from a different table on the same page. M3 does not have a pitch of 20.

It would be easy to "helpfully" correct it. **Don't.** The download button opens that
very page. If the database says one thing and the page says another, the citation
feature is worse than useless — it actively undermines trust. The rule is:

> Capture as printed. Record the defect in `note`. Let a human decide.

The same reasoning applies to the effective date (see 3.4).

## 1.8 Why production is read and testing is written

Invoice history — the entire basis of verification — only exists in the client's
**production** project. But writing to a client's live database from an extraction
script is not a risk worth taking, and the available production credential is read-only
anyway.

So: **read names and invoices from production, write rows to testing.** This is
correct, but it has a consequence that bit once already — the two catalogues differ by
several thousand items, so some matched rows reference items the target project has
never heard of. See 3.6.

## 1.9 Why the price-revision discovery matters most

Late in the work, checking invoice rates against list *by month* revealed this:

```
2025-04 … 2026-04   ~0% of sale lines billed above list
2026-05             14%
2026-06             84%
2026-07             86%
2026-08             90%
```

**Prices were raised ~10% around May–June 2026.** The available PDF is the January 2024
list. So the dataset is accurate to its document and simultaneously ~10% below what is
actually being charged today.

This reframes everything: what first looked like two anomalous SKUs was 1,492 invoice
lines showing a systematic revision. The lesson generalises —

> When many rows disagree with a reference, check whether the *reference* is stale
> before assuming the *rows* are wrong.

The resolution is not to inflate the stored list. It is to obtain the current price
list, or to carry a second effective-dated rate alongside the printed one.

---

# PART 2 — KNOW HOW

## 2.1 Pipeline shape

```
PDF ──pdftotext -layout──► text
      │
      ├─ classify pages          which are price grids?
      ├─ extract cells           → catalogue: 3,229 rows
      ├─ QA gate                 catalogue vs known-good cells   ◄── STOP if this fails
      ├─ match item names        Tally name → catalogue cell
      ├─ verify with invoices    promote to `verified`, derive pack size
      └─ seed the table          one row per stock item name
```

## 2.2 PDF → text

`pdftotext -layout` (poppler). **The `-layout` flag is essential** — it preserves
column positions with whitespace, which is what makes grid parsing possible at all.
Without it the output is reading-order prose and every table collapses.

If a price list has no text layer, this whole approach changes and OCR enters the
picture. Check first.

## 2.3 The two grid styles

Price lists mix layouts. This document had two, needing two parsers:

**Positional grids** — a size label followed by N price columns:

```
1.1/2"     9089   9548  10908   9089   9548  10908   9833  12303  12760
           └──── BSW/BSF ────┘  └──── UNF/UNC ────┘   BSP   BSPT    NPT
```

Parsed by counting **trailing** tokens that are numbers or dashes. Parsing from the
right is what makes it robust — size labels contain spaces (`1.0 X 0.25 #`,
`14X1.0 / 1.25`) while the value block never does. A per-table spec maps column index
to `(thread_form, grade)`.

**Code-anchored grids** — repeated `EDP Code | Price ₹` pairs:

```
M2  0.4  FAB0208213 1112  FAB0205713 1181  FAB0208215 1220 …
```

Parsed by walking tokens left to right: each product code followed by a number emits a
cell; a fresh size label resets the column counter. **This one walk handles both
stacked and side-by-side tables**, because a second size label mid-line naturally
starts a new row.

## 2.4 Making two vocabularies meet

Tally and the PDF write the same size differently. Both sides go through the same
normaliser so they meet in the middle:

```
Tally  1-1/2"       →  strip " , replace - with .  →  1.1/2
PDF    1.1/2"       →  same                        →  1.1/2      ✓

Tally  10 X 1.5     →  parse floats, format %g     →  10 X 1.5
PDF    10.0 X 1.50  →  same                        →  10 X 1.5   ✓
```

Then the catalogue is indexed as `(thread_form, normalised_size, grade) → row`, and a
match is one dictionary lookup.

Thread forms collapse where the document shares a column: `BSW`+`BSF` → `BSW/BSF`,
`UNC`+`UNF` → `UNF/UNC`.

## 2.5 Deriving pack size from invoices

```
modal = most common `rate` across this item's sale lines
base  = catalogue price per piece  (× any documented surcharge)
ratio = modal / base

if ratio is within 0.005 of a whole number and 1 ≤ round(ratio) ≤ 4:
        pack_qty   = round(ratio)      ← invoices override the item name
        confidence = "verified"
else:
        keep the name's guess, record the disagreement, stay "review"
```

Three deliberate choices:

- **Modal, not mean or latest** — one unusual invoice cannot move it.
- **0.005 tolerance** — only a near-exact integer counts. A negotiated rate produces
  something like 1.63 and is correctly rejected.
- **1–4 clamp** — stops a bad cell match from inventing a pack of 37 to force agreement.

## 2.6 The QA gate

A small set of cells is verified by hand against rendered pages *and* against invoice
history. Every extractor run is then checked against that set, and the seed is not
allowed to proceed unless all of them match.

This is what converts "did I read three thousand numbers correctly?" from an act of
faith into a two-second test. **Build this before trusting any extraction.**

## 2.7 Detecting a stale price list

Bucket every sale line by month, compute `invoice rate ÷ list rate`, and count how many
land at 1.00 versus some other constant:

```
month     at list    +10%
2026-04       770       0
2026-06        22     514      ← a revision landed here
```

A clean step change means the reference document is out of date. Scattered ratios mean
individual pricing decisions. **Run this whenever a large fraction of rows disagree** —
it distinguishes "our data is wrong" from "our source is old", which are opposite
problems with opposite fixes.

## 2.8 The table

```sql
create table price_list (
  stock_item_name  text primary key,     -- exact name from the accounting system

  list_rate        numeric not null,      -- displayed; already in the invoice's unit
  unit             text,

  brand            text not null,         -- provenance
  doc_title        text not null,
  effective_from   date not null,
  storage_path     text,                  -- where the PDF lives
  page_no          integer not null,      -- the citation

  price_per_piece  numeric not null,      -- how list_rate was derived
  pack_qty         numeric not null default 1,

  thread_form      text,                  -- so a human can verify the cell
  size             text,
  grade            text,
  edp_code         text,

  confidence       text not null default 'review',
  note             text,
  updated_at       timestamptz not null default now()
);
```

Read-only to the app, writable only by a service key. `price_per_piece` and `pack_qty`
exist so the displayed number is explainable rather than magic — "₹19,666 because
₹9,833 × 2" is a sentence a salesman can repeat to a customer.

## 2.9 Adding another price list

1. `pdftotext -layout new.pdf pages.txt`
2. Classify the pages — which carry price grids?
3. Dump each grid's header block; write a column spec per table.
4. Extend the item-name parser for any new product family.
5. Establish a handful of known-good cells (rendered page + invoice history).
6. Run the extractor; the QA gate must pass before seeding.

Budget most of the time for steps 3 and 4. Extraction is mechanical; **mapping messy
real-world item names to catalogue coordinates is the actual work.**

---

# PART 3 — TRAPS THAT ALREADY BIT

Each of these silently produced *plausible* wrong data. None would have been caught by
looking at the output.

## 3.1 Size-key collision

Page 3 held a 9-column inch table *and* small screw-number tables keyed 0–12.
Normalising away the inch mark made `3"` and `#3` collide, so a ₹1,143 screw price
overwrote a ₹58,444 tap.

**Lesson:** when two labelling systems share a page, keep them distinguishable —
carry a `size_system` alongside the size, and never let normalisation erase the only
thing separating two namespaces.

## 3.2 A units column read as prices

A "Special Pitch" table's Pitch column (`40, 48`) was consumed as two extra price
cells, producing ₹28 taps.

**Lesson:** structural sanity checks catch this instantly. *No tap costs ₹28.* A
plausibility floor on every extracted value is cheap and finds real bugs.

## 3.3 One table per page

Pages carried up to three stacked grids, and sometimes two side by side with different
standards. The one-table-per-page assumption silently dropped a hundred cells.

**Lesson:** derive structure from the document's own headers rather than assuming a
page shape.

## 3.4 Filename metadata is not document metadata

The filename said *Effective-01.01.2024*. The cover page said **EFFECTIVE 08.01.2024**.

**Lesson:** for anything citable, the document wins. Open the cover page.

## 3.5 A silent fallback that mispriced 49 rows

The item-name parser had no concept of long-shank taps, so `TYPE B` and `TYPE C` items
fell through to the `Standard` column — the *short* tap's cheaper price. A ₹1,534 tap
was stored at ₹947.

Only 33 of the 49 had invoice history to catch them; **16 were silently wrong**.

**Lesson:** a fallback that returns a *valid-looking* value is more dangerous than one
that fails. If a name carries a qualifier the parser doesn't understand, prefer
flagging it over quietly defaulting.

**Generalisable technique:** for any row where the invoice disagrees with list, test
whether a *different grade of the same size* matches the invoice exactly. A hit means
the row was matched to the wrong column, and the invoice has just told you the right
one. This found the long-shank bug.

## 3.6 Reading from one database and writing to another

Item names came from production; rows were written to testing. The catalogues differ
by thousands of items, so ~13% of rows referenced items the target had never heard of.

**Lesson:** after seeding, cross-check keys against the target's own catalogue. And
decide deliberately whether orphans should be deleted or kept — they are meaningless in
one project and perfectly valid in the other.

---

# PART 4 — QUICK REFERENCE

| Fact | Value |
|---|---|
| Source document | TOTEM HSS Taps price list, Forbes & Company Limited |
| Effective date | **2024-01-08** (cover page; filename says 01.01 and is wrong) |
| Pages | 36 total, 26 are price grids |
| Catalogue cells extracted | 3,229 across 25 pages |
| Items priced | 850 |
| Confirmed by invoice history | 445 |
| Documented surcharges | left-hand +35%, BSW/BSF +7.5%, nitriding +3.5%, American standard +7.5% |
| Undocumented, observed | **+10% on ~85% of sale lines since June 2026** |
| Not in this document | dies, drills, reamers, centre drills |

## Open questions for the business

1. Is there a **2026 price list**? The +10% pattern says prices moved in mid-2026 and
   the available PDF predates it.
2. Should the screen show the printed list price, the current effective price, or both?
3. Where is the **die** price list? A significant share of stocked items cannot be
   priced without it.
