# Price list pipeline

Turns the TOTEM price-list PDF into rows in the Supabase `price_list` table, which the
Rate / Stock Info screen reads to show an item's list price and cite its source page.

Full background, schema, findings and open questions: **[`PRICE_LIST_HANDOFF.md`](../../PRICE_LIST_HANDOFF.md)** at the repo root.

## Credentials

Nothing secret lives here. `_cfg.py` resolves endpoints and keys at run time from the
two gitignored env files:

| | source | access |
|---|---|---|
| `TEST` / `TEST_KEY` | `.env` → `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` | testing project, read **and write** |
| `PROD` / `PROD_KEY` | `env/deployment.json` | client production, **read only** |

Item names and invoice history are read from PROD because that is where real sale data
lives. Rows are written to TEST because that is the only service key available.
**Never write to PROD with these scripts.**

## Requirements

- Python 3 (`py` on Windows) — standard library only, no pip installs
- `pdftotext` (poppler) on PATH, only if regenerating `pages.txt`

## Run order (v2 — current)

```bash
# 0. only when the PDF revision changes
pdftotext -layout      <price-list.pdf> pages.txt
pdftotext -bbox-layout <price-list.pdf> bbox.xml && gzip -9 -k bbox.xml

python3 match2.py   # names + catalogue -> price_list_rows_v2.csv  (731 rows)
python3 verify.py   # audit table vs PDF -> price_list_audit.csv
python3 seed2.py    # back up, upsert, delete rows no longer matched
python3 verify.py   # re-audit; every row must read TRANSCRIPTION=OK
```

`verify.py` is the gate. It re-derives every seeded price straight from the PDF's word
coordinates and compares. Pass it a CSV to audit a snapshot instead of the live table
(`python3 verify.py price_list_backup_850rows.csv`) — that is what documents a change.

Two independent extractors must agree before anything is trusted: `extract2.py` reads
the `-layout` text by counting tokens, `cat_geom.py`/`edp_geom.py` read word bounding
boxes and place each price under the column header it physically sits beneath. They
currently agree on **all 3,229 cells**, price and size.

### v1 (superseded, kept for reference)

```bash
python3 extract2.py   # -> price_list_items.csv  (3,229 catalogue cells)
python3 qa2.py        # must print "ALL MATCH"
python3 match.py      # -> price_list_rows.csv   (850 rows)
python3 seed.py ; python3 prune.py
```

v1 read item names from production and wrote rows to testing, so 107 seeded rows
referenced items that do not exist in the target project. It also fell back to grade
`Standard` whenever a named grade had no cell, which priced HSS-E and Silver Cut taps
from the plain HSS grids. Do not seed from it.

## What each script does

| Script | |
|---|---|
| `_cfg2.py` | **v2 config.** One project for names, sale history and writes, so no orphan rows are possible. |
| `geom.py` | Word bounding boxes from `bbox.xml(.gz)`, grouped into visual rows. |
| `cat_geom.py` | **Geometric catalogue, pages 3–11.** Each price is placed under the column header it physically sits beneath. Column specs were each confirmed against the rendered page image. |
| `edp_geom.py` | **Geometric catalogue, pages 12–28.** Pairs each price with the EDP code to its left and reads the grade label above its column. Handles side-by-side grids and ignores left-margin standard markers. |
| `match2.py` | **The matcher.** Family-aware, no cross-family grade fallback; size keys carry their measurement system. |
| `verify.py` | **The gate.** Audits each seeded row against the PDF (transcription) and against `match2`'s decision (attribution). |
| `seed2.py` | Backs the table up, upserts the CSV, deletes rows no longer matched. |
| `_cfg.py` | v1 config: endpoints + keys from the env files. |
| `extract2.py` | **The extractor.** Two parsers — positional grids (p3–11) and EDP-anchored grids (p12–28). Column specs live at the top. |
| `qa2.py` | **The QA gate.** Extract vs invoice-verified cells, plus structural checks. |
| `match.py` | Parses Tally item names, matches them to catalogue cells, and lets invoice history decide `pack_qty`. |
| `seed.py` | Batched upsert into `price_list`. |
| `prune.py` | Removes rows with no `stock_items` counterpart in the target project. |
| `crosscheck.py` | Reports the PROD/TEST catalogue drift without changing anything. |
| `phase0.py` | The original smoke test: page 3/8 prices vs 719 real sale lines. |
| `upload.py` | PDF → Storage bucket. **Never successfully run** — blocked by permissions. |
| `pagemap.py` | Classifies all 36 PDF pages: price grid / chart / matter. |
| `headers.py`, `blocks.py`, `tables.py`, `showpage.py` | Layout reconnaissance, used when adding a new document. |
| `items.py`, `names.py` | Item-name reconnaissance against PROD. |
| `ratios.py` | Groups invoice-vs-list disagreements to look for a systematic rule. |

## Data files

| File | |
|---|---|
| `pages.txt` | `pdftotext -layout` output. Committed so the pipeline runs without the source PDF. |
| `bbox.xml.gz` | `pdftotext -bbox-layout` output — per-word coordinates. Committed for the same reason; `geom.py` reads the gzip directly. |
| `price_list_items.csv` | 3,229 catalogue cells, 25 pages. Output of `extract2.py`. |
| `price_list_rows_v2.csv` | **731 matched items — what is seeded.** Output of `match2.py`. |
| `price_list_skipped_v2.csv` | 904 names `match2.py` declined to price, each with a reason. The work queue for wider coverage. |
| `price_list_audit.csv` | Output of `verify.py`: per-item transcription verdict, attribution verdict and action. |
| `price_list_backup_850rows.csv` | The table as it stood before the v2 sync. Restore with `seed2.py` if needed. |
| `price_list_rows.csv` | v1's 850 rows. Superseded — 199 of them were wrong or orphaned. |

## Adding another price list

1. `pdftotext -layout new.pdf pages.txt`
2. `py pagemap.py new.pdf` to find which pages are price grids
3. `py headers.py` to dump each grid's header, then add column specs to `extract2.py`
4. Extend the name parser in `match.py` for the new product family
5. Run the order above; `qa2.py` must pass
