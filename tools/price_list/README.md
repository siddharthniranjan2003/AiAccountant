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

## Run order

```bash
# 0. only if you need to re-extract text from a new PDF revision
pdftotext -layout <price-list.pdf> pages.txt

py extract2.py   # PDF text  -> price_list_items.csv   (3,229 catalogue cells)
py qa2.py        # must print "ALL MATCH" before going further
py match.py      # Tally names -> price_list_rows.csv  (850 matched items)
py seed.py       # upsert into price_list on TEST
py prune.py      # drop rows whose item is absent from this project's stock_items
```

`qa2.py` is the gate. It cross-checks the extract against 64 cells that were
independently verified against real invoice rates; if it does not say `ALL MATCH`,
something in the parser regressed and the seed should not run.

## What each script does

| Script | |
|---|---|
| `_cfg.py` | Endpoints + keys from the env files. Imported by the rest. |
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
| `price_list_items.csv` | 3,229 catalogue cells, 25 pages. Output of `extract2.py`. |
| `price_list_rows.csv` | 850 matched items. Output of `match.py`. **Superset of what is seeded** — testing only holds the 743 whose items exist there. Seed PROD from this file. |

## Adding another price list

1. `pdftotext -layout new.pdf pages.txt`
2. `py pagemap.py new.pdf` to find which pages are price grids
3. `py headers.py` to dump each grid's header, then add column specs to `extract2.py`
4. Extend the name parser in `match.py` for the new product family
5. Run the order above; `qa2.py` must pass
