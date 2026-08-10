"""Match TOTEM Tally item names to catalogue cells -> price_list rows."""
import csv, json, pathlib, re, urllib.parse, urllib.request
from collections import Counter, defaultdict

HERE = pathlib.Path(__file__).parent
from _cfg import PROD, PROD_KEY

KEY = PROD_KEY

DOC = dict(brand="TOTEM", doc_title="TOTEM HSS Taps Price List",
           effective_from="2024-01-08",
           storage_path="price-lists/totem-hpt-2024-01-08.pdf")

def get(url):
    r = urllib.request.Request(url, headers={"apikey": KEY, "Authorization": "Bearer " + KEY})
    return json.load(urllib.request.urlopen(r))

def page(path, **q):
    out, off = [], 0
    while True:
        qs = "&".join(f"{k}={v}" for k, v in q.items())
        b = get(f"{PROD}/{path}?{qs}&limit=1000&offset={off}")
        out += b
        if len(b) < 1000:
            return out
        off += 1000

# ---------------------------------------------------------------- catalogue
cat = list(csv.DictReader((HERE / "price_list_items.csv").open(encoding="utf-8")))

def ninch(s):
    return s.replace('"', "").replace("-", ".").strip()

def nmetric(d, p):
    try:
        return f"{float(d):g} X {float(p):g}"
    except ValueError:
        return None

INDEX = {}
for r in cat:
    if r["size_system"] == "inch":
        k = ninch(r["size"])
    elif r["size_system"] == "metric" and " X " in r["size"].upper():
        m = re.match(r"([\d.]+)\s*X\s*([\d.]+)", r["size"], re.I)
        k = nmetric(*m.groups()) if m else r["size"]
    else:
        k = r["size"]
    INDEX.setdefault((r["thread_form"], k, r["grade"]), r)

# ---------------------------------------------------------------- item names
names = [x["name"] for x in page("stock_items", select="name",
         **{"name": "ilike." + urllib.parse.quote("%TOTEM%"), "order": "name"})]

sales = page("voucher_items", select=urllib.parse.quote(
    "stock_item_name,unit,rate,...vouchers!inner(voucher_type)"),
    **{"stock_item_name": "ilike." + urllib.parse.quote("%TOTEM%"),
       "vouchers.voucher_type": "ilike.*sale*"})
rate_hist, unit_of = defaultdict(list), {}
for s in sales:
    rate_hist[s["stock_item_name"]].append(float(s["rate"]))
    if s.get("unit"):
        unit_of[s["stock_item_name"]] = s["unit"]

# ---------------------------------------------------------------- name parsing
THREADS = {"BSPT":"BSPT","BSP":"BSP","NPTF":None,"NPT":"NPT","BSW":"BSW/BSF","BSF":"BSW/BSF",
           "UNC":"UNF/UNC","UNF":"UNF/UNC","BA":"BA","BSB":"BSB"}
PACK = {"PAIR": 2, "SET": 3}

def parse(name):
    u = re.sub(r"\s+", " ", name.upper()).strip()
    if not re.search(r"\bTAP\b", u) or "NIB" in u or "DIE" in u:
        return None
    lh = bool(re.search(r"\bLH\b", u))
    gold = "GOLD" in u
    grade = "Standard"
    if re.search(r"\bSPPT\b", u): grade = "SPPT"
    elif re.search(r"\b(SF|RS)\b", u): grade = "SF/RS"
    if gold:
        grade = "SPPT GOLD" if grade == "SPPT" else "STD GOLD"
    pack = next((v for k, v in PACK.items() if re.search(rf"\b{k}\b", u)), 1)

    m = re.search(r"\bTAP\s+(\d[\d.]*)\s*X\s*(\.?\d[\d.]*)", u)
    if m:
        size = nmetric(*m.groups())
        if size:
            return dict(thread="Metric Coarse", size=size,
                        grade=grade, pack=pack, lh=lh, gold=gold)
        return None
    m = re.search(r"\bTAP\s+([0-9][0-9/.\-]*)\"?\s+(BSPT|BSP|NPTF|NPT|BSW|BSF|UNC|UNF|BSB|BA)\b", u)
    if m:
        t = THREADS.get(m.group(2))
        if not t:
            return None
        return dict(thread=t, size=ninch(m.group(1)), grade=grade, pack=pack, lh=lh, gold=gold)
    return None

# ---------------------------------------------------------------- match
rows, stats = [], Counter()
unmatched = []
for name in names:
    p = parse(name)
    if not p:
        stats["name not parsed"] += 1; unmatched.append((name, "unparsed")); continue
    cell = INDEX.get((p["thread"], p["size"], p["grade"]))
    if cell is None and p["grade"] != "Standard":
        cell = INDEX.get((p["thread"], p["size"], "Standard"))
    if cell is None:
        stats["no catalogue cell"] += 1; unmatched.append((name, f"{p['thread']} {p['size']} {p['grade']}")); continue

    per_pc = float(cell["price_per_piece"])
    pack, note, conf = p["pack"], "", "review"
    if p["lh"]:
        note = "Left-hand tap: list +35% per price-list note 4 (p.27)"

    hist = rate_hist.get(name)
    if hist:
        modal = Counter(hist).most_common(1)[0][0]
        base = per_pc * (1.35 if p["lh"] else 1)
        ratio = modal / base if base else 0
        if abs(ratio - round(ratio)) < 0.005 and 1 <= round(ratio) <= 4:
            pack = round(ratio)                      # oracle decides the pack size
            conf = "verified"
            stats["verified by invoice"] += 1
        else:
            note = (note + " | " if note else "") + \
                   f"invoice rate {modal:,.2f} != list {base * pack:,.2f}"
            stats["invoice disagrees"] += 1
    else:
        stats["no sale history (review)"] += 1

    list_rate = round(per_pc * (1.35 if p["lh"] else 1) * pack, 2)
    rows.append(dict(stock_item_name=name, list_rate=f"{list_rate:.2f}",
                     unit=unit_of.get(name, ""), brand=DOC["brand"], doc_title=DOC["doc_title"],
                     effective_from=DOC["effective_from"], storage_path=DOC["storage_path"],
                     page_no=cell["page_no"], price_per_piece=f"{per_pc:.2f}", pack_qty=pack,
                     thread_form=cell["thread_form"], size=cell["size"], grade=cell["grade"],
                     edp_code=cell["edp_code"], confidence=conf,
                     note=(note + (" | " if note and cell["source_note"] else "") + cell["source_note"]).strip(" |")))

out = HERE / "price_list_rows.csv"
with out.open("w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

print(f"TOTEM item names scanned : {len(names):,}")
print(f"MATCHED -> price_list    : {len(rows):,}")
for k, v in stats.most_common():
    print(f"   {v:>5}  {k}")
print(f"\nconfidence: " + ", ".join(f"{k}={v}" for k, v in Counter(r['confidence'] for r in rows).items()))
print(f"\nunmatched sample:")
for n, why in unmatched[:10]:
    print(f"   {n[:52]:54s} {why}")
