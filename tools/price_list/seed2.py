"""Sync the price_list table to price_list_rows_v2.csv.

Backs the current table up to price_list_backup_<n>rows.csv first, then upserts every
row in the CSV and deletes any seeded row the CSV no longer contains. Writes to the
project in .env (testing) only.
"""
import csv, pathlib, sys, urllib.parse, urllib.request
from _cfg2 import REST, page, send, _req, CTX

HERE = pathlib.Path(__file__).parent
COLS = ["stock_item_name", "list_rate", "unit", "brand", "doc_title", "effective_from",
        "storage_path", "page_no", "price_per_piece", "pack_qty", "thread_form", "size",
        "grade", "edp_code", "confidence", "note"]

rows = list(csv.DictReader((HERE / "price_list_rows_v2.csv").open(encoding="utf-8")))
if not rows:
    sys.exit("price_list_rows_v2.csv is empty - run match2.py")

current = page("price_list", select="*", order="stock_item_name")
backup = HERE / f"price_list_backup_{len(current)}rows.csv"
if current:
    with backup.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(current[0].keys()))
        w.writeheader(); w.writerows(current)
    print(f"backed up {len(current)} existing rows -> {backup.name}")

payload = []
for r in rows:
    d = {c: (r.get(c) or None) for c in COLS}
    d["page_no"] = int(r["page_no"])
    d["pack_qty"] = float(r["pack_qty"])
    d["list_rate"] = float(r["list_rate"])
    d["price_per_piece"] = float(r["price_per_piece"])
    payload.append(d)

for i in range(0, len(payload), 250):
    chunk = payload[i:i+250]
    st, body = send("price_list", chunk, "POST",
                    {"Prefer": "resolution=merge-duplicates,return=minimal"})
    print(f"  upsert {i+1:>4}-{i+len(chunk):<4} -> HTTP {st} {body}")

keep = {r["stock_item_name"] for r in rows}
stale = [r["stock_item_name"] for r in current if r["stock_item_name"] not in keep]
for n in stale:
    url = f"{REST}/price_list?stock_item_name=eq.{urllib.parse.quote(n, safe='')}"
    urllib.request.urlopen(_req(url, "DELETE", extra={"Prefer": "return=minimal"}), context=CTX)
print(f"deleted {len(stale)} rows no longer matched")

after = page("price_list", select="stock_item_name,confidence")
from collections import Counter
print(f"\nprice_list now holds {len(after)} rows: "
      + ", ".join(f"{k}={v}" for k, v in Counter(r["confidence"] for r in after).items()))
