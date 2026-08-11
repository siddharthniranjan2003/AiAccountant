"""Audit the seeded price_list table against the PDF, row by row.

Two independent questions are asked of every row:

  1. TRANSCRIPTION - is the stored price the number actually printed at the
     coordinates the row claims (page / thread / size / grade)? Checked against
     cat_geom, which locates each price by its x-position under the printed column
     header, so it shares no code path with the extractor that produced the row.
  2. ATTRIBUTION  - are those the RIGHT coordinates for that item? Checked against
     match2's decision for the same name.

A row can pass 1 and fail 2: an HSS-E cobalt tap priced from the plain HSS grid has a
perfectly transcribed number that belongs to a different product.

Output: price_list_audit.csv  (one row per audited item, no upload)
"""
import csv, pathlib, re, sys

from _cfg2 import page
from cat_geom import build as build_positional, norm

HERE = pathlib.Path(__file__).parent

# Default: audit the live table. Pass a CSV snapshot (e.g. the backup seed2.py writes)
# to audit the state *before* a sync, which is what documents a change.
if len(sys.argv) > 1:
    live = {r["stock_item_name"]: r for r in csv.DictReader(open(sys.argv[1], encoding="utf-8"))}
    print(f"baseline: {sys.argv[1]} ({len(live)} rows)")
else:
    live = {r["stock_item_name"]: r
            for r in page("price_list", select="*", order="stock_item_name")}
try:
    new = {r["stock_item_name"]: r for r in
           csv.DictReader((HERE / "price_list_rows_v2.csv").open(encoding="utf-8"))}
    skipped = {r[0]: r[1] for r in
               list(csv.reader((HERE / "price_list_skipped_v2.csv").open(encoding="utf-8")))[1:]}
except FileNotFoundError:
    sys.exit("run match2.py first (needs price_list_rows_v2.csv)")

CELLS = build_positional()
stock = {x["name"] for x in page("stock_items", select="name",
         **{"name": "ilike.%25TOTEM%25"})}

def pdf_price(r):
    hit = CELLS.get((int(r["page_no"]), r["thread_form"], norm(r["size"]), r["grade"]))
    return hit[0] if hit else None

def is_lh(n): return bool(re.search(r"\bLH\b", n.upper()))

out = []
for name in sorted(set(live) | set(new)):
    o, n = live.get(name), new.get(name)
    rec = dict(stock_item_name=name, transcription="", attribution="", action="",
               db_price_per_piece="", pdf_price_per_piece="", v2_price_per_piece="",
               db_list_rate="", v2_list_rate="", page_no="", thread_form="", size="",
               grade="", pack_qty="", confidence="", reason="")

    if o:
        pdf = pdf_price(o)
        db = float(o["price_per_piece"])
        exp = round(db * (1.35 if is_lh(name) else 1) * float(o["pack_qty"] or 1), 2)
        rec.update(db_price_per_piece=f"{db:.2f}", db_list_rate=f"{float(o['list_rate']):.2f}",
                   pdf_price_per_piece="" if pdf is None else pdf,
                   page_no=o["page_no"], thread_form=o["thread_form"], size=o["size"],
                   grade=o["grade"], pack_qty=f"{float(o['pack_qty'] or 1):g}",
                   confidence=o["confidence"])
        if pdf is None:
            rec["transcription"] = "NO_CELL_AT_THOSE_COORDS"
        elif abs(pdf - db) > 0.005:
            rec["transcription"] = "PRICE_MISMATCH"
        elif abs(exp - float(o["list_rate"])) > 0.02:
            rec["transcription"] = "LIST_RATE_MATH"
        else:
            rec["transcription"] = "OK"

    if n:
        rec.update(v2_price_per_piece=f"{float(n['price_per_piece']):.2f}",
                   v2_list_rate=f"{float(n['list_rate']):.2f}")
        if not o:
            rec.update(action="ADD", attribution="OK", page_no=n["page_no"],
                       thread_form=n["thread_form"], size=n["size"], grade=n["grade"],
                       pack_qty=f"{float(n['pack_qty']):g}", confidence=n["confidence"],
                       reason="matched by v2; not previously seeded")
        elif abs(float(n["price_per_piece"]) - float(o["price_per_piece"])) > 0.005:
            rec.update(action="PRICE_CORRECTED", attribution="WRONG_CELL",
                       reason="v2 resolves this name to a different cell; see size_system")
        else:
            rec.update(action="KEEP", attribution="OK")
    else:
        why = ("item absent from this project's stock_items"
               if name not in stock else skipped.get(name, "not matched by v2"))
        rec.update(action="DROP", attribution="WRONG_FAMILY_OR_ABSENT", reason=why)

    out.append(rec)

with (HERE / "price_list_audit.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys())); w.writeheader(); w.writerows(out)

from collections import Counter
print(f"audited {len(out)} items -> price_list_audit.csv\n")
print("TRANSCRIPTION (stored price vs the number printed at those coords)")
for k, v in Counter(r["transcription"] for r in out if r["transcription"]).most_common():
    print(f"   {v:>5}  {k}")
print("\nACTION")
for k, v in Counter(r["action"] for r in out).most_common():
    print(f"   {v:>5}  {k}")
print("\nDROP reasons")
for k, v in Counter(r["reason"].split(":")[0] for r in out if r["action"] == "DROP").most_common():
    print(f"   {v:>5}  {k}")
