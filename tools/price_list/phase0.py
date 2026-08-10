"""Phase 0 smoke test: page 3 (+ page 8 GOLD) tap prices vs actual sale invoice rates."""
import json, re, urllib.parse, urllib.request
from collections import Counter, defaultdict

from _cfg import PROD, PROD_KEY

BASE = PROD + "/voucher_items"
KEY = PROD_KEY

# --- page 3: TOTEM HSS Hand/Short Machine taps, BS-949, Standard grade (Rs/piece)
P3 = {
    "BSP":  {"1/8":671,"1/4":1023,"3/8":1501,"1/2":2269,"5/8":2513,"3/4":3371,"7/8":4159,
             "1":5257,"1.1/8":7235,"1.1/4":7884,"1.1/2":9833,"1.3/4":15065,"2":17648,
             "2.1/4":30501,"2.1/2":44006,"2.3/4":49104,"3":58444,"3.1/2":73675,"4":92611},
    "BSPT": {"1/8":914,"1/4":1595,"3/8":2049,"1/2":3057,"3/4":4528,"1":7034,"1.1/4":10061,
             "1.1/2":12303,"2":22519,"2.1/2":69606,"3":91084,"3.1/2":120074,"4":151224},
}
# --- page 8: TOTEM GOLD (TiN coated), STD GOLD
P8 = {
    "BSP":  {"1/8":902,"1/4":1328,"3/8":2006,"1/2":2804,"5/8":3057,"3/4":3947,"7/8":4765,
             "1":5905,"1.1/8":8295,"1.1/4":8968,"1.1/2":11328,"1.3/4":17654,"2":20335,
             "2.1/4":34122,"2.1/2":48137,"2.3/4":53876,"3":63569,"3.1/2":79783,"4":99432},
    "BSPT": {"1/8":1154,"1/4":1922,"3/8":2575,"1/2":3622,"3/4":5149,"1":7748,"1.1/4":11228,
             "1.1/2":13890,"2":25390,"2.1/2":74520,"3":97224,"3.1/2":160257},
}

def get(url):
    req = urllib.request.Request(url, headers={"apikey": KEY, "Authorization": "Bearer " + KEY})
    with urllib.request.urlopen(req) as r:
        return json.load(r)

sel = urllib.parse.quote("stock_item_name,quantity,unit,rate,...vouchers!inner(voucher_type)")
pat = urllib.parse.quote("%HSS TAP%BSP%TOTEM%")
rows = get(f"{BASE}?select={sel}&stock_item_name=ilike.{pat}"
           f"&vouchers.voucher_type=ilike.*sale*&limit=20000")
print(f"sale lines pulled: {len(rows)}")

rates = defaultdict(list)
units = {}
for r in rows:
    rates[r["stock_item_name"]].append(float(r["rate"]))
    units[r["stock_item_name"]] = r.get("unit")

def norm_size(s):
    s = s.replace('"', "").replace("-", ".").strip()
    return s

def parse(name):
    """Tally name -> (thread, size, pack_qty, gold)"""
    n = name.upper()
    m = re.search(r"HSS TAP\s+([0-9./\-]+)\"?\s+(BSPT|BSP)\b", n)
    if not m:
        return None
    size, thread = norm_size(m.group(1)), m.group(2)
    pack = 2 if re.search(r"\bPAIR\b", n) else 1
    return thread, size, pack, ("GOLD" in n)

ok = mism = nomatch = 0
mismatches, unmatched = [], []
for name, rs in sorted(rates.items()):
    p = parse(name)
    if not p:
        unmatched.append((name, "name did not parse")); nomatch += 1; continue
    thread, size, pack, gold = p
    table = P8 if gold else P3
    per_pc = table.get(thread, {}).get(size)
    if per_pc is None:
        unmatched.append((name, f"no {thread} {size} cell on page {8 if gold else 3}")); nomatch += 1; continue
    expected = per_pc * pack
    modal = Counter(rs).most_common(1)[0][0]
    if abs(modal - expected) < 0.01:
        ok += 1
    else:
        mism += 1
        mismatches.append((name, expected, modal, per_pc, pack, len(rs)))

print(f"\n=== {ok+mism+nomatch} distinct items with sale history ===")
print(f"  MATCH     {ok}")
print(f"  MISMATCH  {mism}")
print(f"  NO CELL   {nomatch}")

if mismatches:
    print("\n--- mismatches (expected vs invoice modal rate) ---")
    for n, e, m, pc, pk, c in mismatches:
        print(f"  {n:42s} exp {e:>10,.2f}  inv {m:>10,.2f}   ratio {m/e:.4f}  ({c} lines)")

print("\n--- every BSPT BOT item, to test the 'BOT surcharge' theory ---")
for name, rs in sorted(rates.items()):
    if "BSPT" in name.upper() and "BOT" in name.upper():
        thread, size, pack, gold = parse(name)
        exp = (P8 if gold else P3).get(thread, {}).get(size, 0) * pack
        modal = Counter(rs).most_common(1)[0][0]
        tag = "match" if abs(modal - exp) < 0.01 else f"+{(modal/exp-1)*100:.1f}%"
        print(f"  {name:42s} exp {exp:>9,.0f}  inv {modal:>9,.0f}   {tag}")
if unmatched:
    print("\n--- no catalogue cell ---")
    for n, why in unmatched:
        print(f"  {n:42s} {why}")
