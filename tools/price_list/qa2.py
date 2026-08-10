"""QA v2: cross-check the extract against the invoice-verified page 3 / page 8 cells."""
import csv, pathlib, re
from collections import Counter
HERE = pathlib.Path(__file__).parent
rows = list(csv.DictReader((HERE / "price_list_items.csv").open(encoding="utf-8")))

P3 = {
 "BSP":  {"1/8":671,"1/4":1023,"3/8":1501,"1/2":2269,"5/8":2513,"3/4":3371,"7/8":4159,
          "1":5257,"1.1/8":7235,"1.1/4":7884,"1.1/2":9833,"1.3/4":15065,"2":17648,
          "2.1/4":30501,"2.1/2":44006,"2.3/4":49104,"3":58444,"3.1/2":73675,"4":92611},
 "BSPT": {"1/8":914,"1/4":1595,"3/8":2049,"1/2":3057,"3/4":4528,"1":7034,"1.1/4":10061,
          "1.1/2":12303,"2":22519,"2.1/2":69606,"3":91084,"3.1/2":120074,"4":151224},
}
P8 = {
 "BSP":  {"1/8":902,"1/4":1328,"3/8":2006,"1/2":2804,"5/8":3057,"3/4":3947,"7/8":4765,
          "1":5905,"1.1/8":8295,"1.1/4":8968,"1.1/2":11328,"1.3/4":17654,"2":20335,
          "2.1/4":34122,"2.1/2":48137,"2.3/4":53876,"3":63569,"3.1/2":79783,"4":99432},
 "BSPT": {"1/8":1154,"1/4":1922,"3/8":2575,"1/2":3622,"3/4":5149,"1":7748,"1.1/4":11228,
          "1.1/2":13890,"2":25390,"2.1/2":74520,"3":97224,"3.1/2":127932,"4":160257},
}
def norm(s): return s.replace('"', "").strip()

bad = tot = 0
for page, table, grade in [(3, P3, "Standard"), (8, P8, "STD GOLD")]:
    got = {}
    for r in rows:
        if int(r["page_no"]) == page and r["grade"] == grade and r["size_system"] == "inch":
            got[(r["thread_form"], norm(r["size"]))] = int(r["price_per_piece"])
    for thread, want in table.items():
        for size, price in want.items():
            tot += 1
            g = got.get((thread, size))
            if g != price:
                print(f"  MISMATCH p{page} {thread} {size}: expected {price}, extract {g}")
                bad += 1
print(f"\nchecked {tot} invoice-verified cells -> {'ALL MATCH' if not bad else str(bad)+' WRONG'}")

print("\n--- structural checks ---")
print(f"total rows            : {len(rows):,}")
prices = [int(r["price_per_piece"]) for r in rows]
print(f"price range           : {min(prices):,} .. {max(prices):,}")
low = [r for r in rows if int(r["price_per_piece"]) < 100]
print(f"rows priced under 100 : {len(low)}")
for r in low[:6]:
    print(f"    p{r['page_no']} {r['thread_form']} {r['size']} {r['grade']} = {r['price_per_piece']}")
key = Counter((r["page_no"], r["standard"], r["thread_form"], r["size"], r["grade"]) for r in rows)
dup = [k for k, c in key.items() if c > 1]
print(f"duplicate natural keys: {len(dup)}")
for k in dup[:6]:
    print("    ", k)
edp = Counter(r["edp_code"] for r in rows if r["edp_code"])
print(f"duplicate EDP codes   : {len([c for c in edp.values() if c>1])}")
