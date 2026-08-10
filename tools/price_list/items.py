"""What TOTEM items exist, grouped by product family."""
import json, re, urllib.parse, urllib.request
from collections import Counter

from _cfg import PROD, PROD_KEY

KEY = PROD_KEY
BASE = PROD + "/stock_items"

def get(url):
    req = urllib.request.Request(url, headers={"apikey": KEY, "Authorization": "Bearer " + KEY})
    with urllib.request.urlopen(req) as r:
        return json.load(r)

names, off = [], 0
while True:
    pat = urllib.parse.quote("%TOTEM%")
    batch = get(f"{BASE}?select=name&name=ilike.{pat}&order=name&limit=1000&offset={off}")
    names += [b["name"] for b in batch]
    if len(batch) < 1000:
        break
    off += 1000
print(f"TOTEM items: {len(names)}\n")

def family(n):
    u = n.upper()
    for k in ["ROUND DIE", "DIE NUT", "HSS LONG TAP", "CARBON TAP", "HSS TAP",
              "SPIRAL", "MACHINE TAP", "NUT TAP", "REAMER", "DRILL", "END MILL",
              "HAND TAP", "PIPE TAP", "TAP"]:
        if k in u:
            return k
    return "(other)"

fam = Counter(family(n) for n in names)
for k, c in fam.most_common():
    print(f"  {c:>5}  {k}")

print("\n--- thread systems seen in HSS TAP names ---")
th = Counter()
for n in names:
    if "HSS TAP" in n.upper():
        for t in ["BSPT","BSP","NPT","BSW","BSF","UNC","UNF","BA","MM","METRIC"]:
            if re.search(rf"\b{t}\b", n.upper()):
                th[t] += 1; break
        else:
            th["(metric M-size or unknown)"] += 1
for k, c in th.most_common():
    print(f"  {c:>5}  {k}")

print("\n--- sample of (other) ---")
for n in [x for x in names if family(x) == "(other)"][:18]:
    print("   ", n)
