import json, re, urllib.parse, urllib.request, random
from _cfg import PROD, PROD_KEY
KEY=PROD_KEY
B=PROD+"/stock_items"
def get(u):
    r=urllib.request.Request(u,headers={"apikey":KEY,"Authorization":"Bearer "+KEY})
    return json.load(urllib.request.urlopen(r))
names=[]; off=0
while True:
    b=get(f"{B}?select=name&name=ilike.{urllib.parse.quote('%TAP%TOTEM%')}&order=name&limit=1000&offset={off}")
    names+=[x["name"] for x in b]
    if len(b)<1000: break
    off+=1000
print("tap-ish TOTEM items:",len(names))
inch=[n for n in names if re.search(r"\b(BSP|BSPT|NPT|BSW|BSF|UNC|UNF|BA)\b",n.upper())]
met=[n for n in names if n not in inch]
print("\n--- 22 metric-style names ---")
for n in met[:22]: print("   ",n)
print("\n--- variant tokens seen across all tap names ---")
from collections import Counter
toks=Counter()
for n in names:
    for t in re.findall(r"\b[A-Z]{2,6}\b", n.upper()):
        if t not in {"HSS","TAP","TOTEM","LONG","CARBON","SET"}: toks[t]+=1
for t,c in toks.most_common(28): print(f"   {c:>5}  {t}")
