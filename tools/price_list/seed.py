"""Seed price_list in the TESTING project from price_list_rows.csv."""
import csv, json, pathlib, re, urllib.parse, urllib.request

HERE = pathlib.Path(__file__).parent
from _cfg import TEST as URL, TEST_KEY as KEY
H = {"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"}

def call(method, path, body=None, extra=None):
    h = dict(H, **(extra or {}))
    req = urllib.request.Request(f"{URL}/{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers=h)
    with urllib.request.urlopen(req) as r:
        return r.read(), dict(r.headers)

rows = list(csv.DictReader((HERE / "price_list_rows.csv").open(encoding="utf-8")))
print(f"rows to seed: {len(rows):,}")

# --- does TESTING actually carry these item names? -------------------------
probe = rows[0]["stock_item_name"]
_, hd = call("GET", "stock_items?select=name&limit=1", extra={"Prefer": "count=exact"})
print("testing stock_items count:", hd.get("Content-Range"))
sample = [r["stock_item_name"] for r in rows[:200]]
found = 0
for n in sample:
    body, _ = call("GET", "stock_items?select=name&name=eq." + urllib.parse.quote(n, safe=""))
    found += 1 if json.loads(body) else 0
print(f"of the first 200 matched names, present in TESTING: {found}")

# --- seed -------------------------------------------------------------------
for r in rows:
    r["page_no"] = int(r["page_no"])
    r["pack_qty"] = float(r["pack_qty"])
    r["list_rate"] = float(r["list_rate"])
    r["price_per_piece"] = float(r["price_per_piece"])
    for k in ("unit", "edp_code", "note"):
        r[k] = r[k] or None

B = 200
for i in range(0, len(rows), B):
    chunk = rows[i:i+B]
    call("POST", "price_list", chunk,
         extra={"Prefer": "resolution=merge-duplicates,return=minimal"})
    print(f"  seeded {min(i+B, len(rows)):>5}/{len(rows)}")

_, hd = call("GET", "price_list?select=stock_item_name&limit=1", extra={"Prefer": "count=exact"})
print("\nprice_list now holds:", hd.get("Content-Range"))
