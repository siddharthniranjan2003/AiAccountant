import csv, pathlib, re
from collections import Counter
HERE=pathlib.Path(__file__).parent
rows=list(csv.DictReader((HERE/"price_list_rows.csv").open(encoding="utf-8")))
bad=[r for r in rows if "invoice rate" in r["note"]]
print(f"disagreements: {len(bad)}")
rat=Counter()
for r in bad:
    m=re.search(r"invoice rate ([\d,]+\.\d+) != list ([\d,]+\.\d+)", r["note"])
    if m:
        inv=float(m.group(1).replace(",","")); lst=float(m.group(2).replace(",",""))
        rat[round(inv/lst,3)]+=1
print("\nmost common invoice/list ratios:")
for v,c in rat.most_common(14):
    print(f"   x{v:<7} {c:>4}")
print("\nLH share of disagreements:", sum(1 for r in bad if " LH " in r["stock_item_name"].upper()))
print("SET share:", sum(1 for r in bad if re.search(r"\bSET\b",r["stock_item_name"].upper())))
print("\nsamples:")
for r in bad[:8]:
    print(f"   {r['stock_item_name'][:46]:48s} pack={r['pack_qty']} {r['note'][:60]}")
