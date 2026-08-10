"""How many seeded price_list names actually exist in TESTING's stock_items?"""
import csv, json, pathlib, re, urllib.parse, urllib.request

HERE = pathlib.Path(__file__).parent
from _cfg import TEST, TEST_KEY, PROD, PROD_KEY

TKEY, PKEY = TEST_KEY, PROD_KEY

def page(base, key, path, **q):
    out, off = [], 0
    while True:
        qs = "&".join(f"{k}={v}" for k, v in q.items())
        r = urllib.request.Request(f"{base}/{path}?{qs}&limit=1000&offset={off}",
                                   headers={"apikey": key, "Authorization": "Bearer " + key})
        b = json.load(urllib.request.urlopen(r))
        out += b
        if len(b) < 1000:
            return out
        off += 1000

probe = "CARBON TAP 3 X .5 SET TOTEM"
for label, base, key in [("PROD", PROD, PKEY), ("TESTING", TEST, TKEY)]:
    hit = page(base, key, "stock_items", select="name",
               **{"name": "eq." + urllib.parse.quote(probe, safe="")})
    print(f"{label:8s} has '{probe}': {bool(hit)}")

test_names = {x["name"] for x in page(TEST, TKEY, "stock_items", select="name")}
prod_names = {x["name"] for x in page(PROD, PKEY, "stock_items", select="name")}
print(f"\nstock_items  PROD={len(prod_names):,}  TESTING={len(test_names):,}")

seeded = [r["stock_item_name"] for r in
          csv.DictReader((HERE / "price_list_rows.csv").open(encoding="utf-8"))]
missing = [n for n in seeded if n not in test_names]
print(f"\nseeded rows                    : {len(seeded):,}")
print(f"  present in TESTING stock_items: {len(seeded)-len(missing):,}")
print(f"  ORPHANED in TESTING           : {len(missing):,}")
print("\norphan samples:")
for n in missing[:12]:
    print("   ", n)
