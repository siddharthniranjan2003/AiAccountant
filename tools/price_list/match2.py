"""Matcher v2: Tally item names -> price_list rows.

Differences from match.py (v1), each driven by an audit finding:

1. No cross-family grade fallback. v1 fell back to grade "Standard" whenever the
   named grade had no cell, which silently priced HSS-E / Silver Cut / SPIREX taps
   from the plain HSS grids on pages 3-5. Those products are 2-3x more expensive,
   so the band showed a badly understated price under a page citation that did not
   contain the item. Such names are now excluded and reported, not guessed at.
2. Catalogue comes from the geometric extractor (cat_geom), where each price is
   located by its x-position under the printed column header.
3. Names, sale history and the write target are all the SAME project, so every row
   references an item that exists there and no orphan-pruning pass is needed.
4. The left-hand surcharge cites page 28, where the notes block actually is.

Output: price_list_rows_v2.csv
"""
import csv, json, pathlib, re, urllib.parse
from collections import Counter, defaultdict

from _cfg2 import page
from cat_geom import build as build_positional

HERE = pathlib.Path(__file__).parent
Q = urllib.parse.quote

DOC = dict(brand="TOTEM", doc_title="TOTEM HSS Taps Price List",
           effective_from="2024-01-08",
           storage_path="price-lists/totem-hpt-2024-01-08.pdf")
LH_NOTE = "Left-hand tap: list +35% per price-list note 4 (p.28)"

# ---------------------------------------------------------------- size keys
# A size key carries its measurement system. Without that, stripping the inch mark
# makes the 3" BSP tap and the #3 BA screw tap collide on "3" - the collision that
# once let a Rs 1,143 BA price overwrite a Rs 58,444 BSP one.
FLAGS = re.compile(r"[#~*]")

def system_of(s):
    s = FLAGS.sub("", s).strip()
    if re.search(r"\dX|X\s*[\d.]", s.upper()):   return "metric"
    if re.fullmatch(r"\d{1,2}", s):              return "number"
    return "inch"

def sizekeys(s):
    """-> list of keys; a label like '4.0 X 0.35/0.50*' covers two pitches."""
    s = FLAGS.sub("", str(s)).upper().replace("”", '"').strip()
    m = re.match(r"^([\d.]+)\s*X\s*([\d./]+)$", s)
    if m:
        out = []
        for p in m.group(2).split("/"):
            try:
                out.append(f"{float(m.group(1)):g}X{float(p):g}")
            except ValueError:
                pass
        return out or [re.sub(r"\s+", "", s)]
    s = s.replace('"', "").replace("-", ".")
    return [re.sub(r"\s+", "", s)]

# ---------------------------------------------------------------- catalogue
CELLS = build_positional()
INDEX = {}
for (pg, thread, _n, grade), (price, raw_size, syst, cnote) in CELLS.items():
    if pg >= 11:                                 # 11+ are HSSE / Silver Cut, matched separately
        continue
    for k in sizekeys(raw_size):
        INDEX.setdefault((thread, system_of(raw_size), k, grade), dict(
            page_no=pg, thread_form=thread, size=raw_size, grade=grade,
            price_per_piece=price, size_system=syst, source_note=cnote))

# ---------------------------------------------------------------- source data
names = [x["name"] for x in page("stock_items", select="name",
         **{"name": "ilike." + Q("%TOTEM%"), "order": "name"})]
sales = page("voucher_items", select=Q("stock_item_name,unit,rate,...vouchers!inner(voucher_type)"),
             **{"stock_item_name": "ilike." + Q("%TOTEM%"),
                "vouchers.voucher_type": "ilike.*sale*"})
rate_hist, unit_of = defaultdict(list), {}
for s in sales:
    if s.get("rate"):
        rate_hist[s["stock_item_name"]].append(float(s["rate"]))
    if s.get("unit"):
        unit_of[s["stock_item_name"]] = s["unit"]

# ---------------------------------------------------------------- name parsing
THREADS = {"BSPT": "BSPT", "BSP": "BSP", "NPTF": None, "NPT": "NPT",
           "BSW": "BSW/BSF", "BSF": "BSW/BSF", "UNC": "UNF/UNC", "UNF": "UNF/UNC",
           "BA": "BA", "BSB": "BSB"}
PACK = {"PAIR": 2, "SET": 3}

# families this price list does not cover, or covers on pages we do not match against
SILVER_CUT = re.compile(r"\b(S[A-Z]{0,2}\d)\b")          # SA3 SB3 SC4 SD1 SBU3 SAS5 ...
OFF_BOOK = [
    (re.compile(r"\bSOLID\s+CARBIDE\b"), "solid carbide - not in this HSS price list"),
    (re.compile(r"\bHSS[- ]?E\b"),       "HSS-E: priced on p11/p12-28, not matched yet"),
    (re.compile(r"\bSPIREX\b"),          "SPIREX: page 11 HSSE grid, not matched yet"),
    (re.compile(r"\bXL\b"),              "XL: page 11 HSSE grid, not matched yet"),
]

def parse(name):
    """-> (spec, None) if priceable from pages 3-10, else (None, reason)"""
    u = re.sub(r"\s+", " ", name.upper()).strip()
    if not re.search(r"\bTAP\b", u):      return None, "not a tap"
    if "NIB" in u or "DIE" in u:          return None, "nib/die - not a tap grid"
    for pat, why in OFF_BOOK:
        if pat.search(u):                 return None, why
    if SILVER_CUT.search(u):
        return None, f"Silver Cut grade {SILVER_CUT.search(u).group(1)}: p12-28, not matched yet"

    lh   = bool(re.search(r"\bLH\b", u))
    gold = "GOLD" in u
    grade = "Standard"
    if re.search(r"\bSPPT\b", u):        grade = "SPPT"
    elif re.search(r"\b(SF|RS)\b", u):   grade = "SF/RS"
    if gold:
        grade = "SPPT GOLD" if grade == "SPPT" else "STD GOLD"
    pack = next((v for k, v in PACK.items() if re.search(rf"\b{k}\b", u)), 1)

    m = re.search(r"\bTAP\s+(\d[\d.]*)\s*X\s*(\.\s*\d[\d.]*|\d[\d.]*)", u)
    if m:
        try:
            size = f"{float(m.group(1)):g} X {float(m.group(2).replace(' ', '')):g}"
        except ValueError:
            return None, "unparseable metric size"
        return dict(thread="Metric Coarse", size=size, system="metric",
                    grade=grade, pack=pack, lh=lh), None

    # the inch mark must stay inside the group: without it 1" reads as BA number 1
    m = re.search(r"\bTAP\s+([0-9][0-9/.\-]*\"?)\s*(BSPT|BSP|NPTF|NPT|BSW|BSF|UNC|UNF|BSB|BA)\b", u)
    if m:
        t = THREADS.get(m.group(2))
        if not t: return None, f"thread {m.group(2)} not in this price list"
        return dict(thread=t, size=m.group(1), system=system_of(m.group(1)),
                    grade=grade, pack=pack, lh=lh), None
    return None, "size/thread not recognised"

# ---------------------------------------------------------------- match
rows, stats, skipped = [], Counter(), []
for name in names:
    p, why = parse(name)
    if p is None:
        stats[why.split(":")[0]] += 1
        skipped.append((name, why))
        continue

    # thread/size/grade must all be present in the catalogue - no fallback.
    cell = next((INDEX[k] for k in
                 ((p["thread"], p["system"], sk, p["grade"]) for sk in sizekeys(p["size"]))
                 if k in INDEX), None)
    if cell is None:
        stats["no cell for that thread/size/grade"] += 1
        skipped.append((name, f"no cell: {p['thread']} {p['size']} {p['grade']}"))
        continue

    per_pc = float(cell["price_per_piece"])
    pack, conf = p["pack"], "review"
    notes = [LH_NOTE] if p["lh"] else []
    if cell["source_note"]:
        notes.append(cell["source_note"])

    hist = rate_hist.get(name)
    if hist:
        modal = Counter(hist).most_common(1)[0][0]
        base  = per_pc * (1.35 if p["lh"] else 1)
        ratio = modal / base if base else 0
        if abs(ratio - round(ratio)) < 0.005 and 1 <= round(ratio) <= 4:
            pack, conf = round(ratio), "verified"        # the invoice decides the pack size
            stats["verified by invoice"] += 1
        else:
            notes.append(f"invoice rate {modal:,.2f} != list {base * pack:,.2f}")
            stats["invoice disagrees (review)"] += 1
    else:
        stats["no sale history (review)"] += 1

    # The band renders "LIST PRICE - PER <unit>", so a null unit is a blank label.
    # Units come from sale history; items never sold have none. Deriving it from the
    # name instead agrees with the recorded unit on 527 of 528 rows that have both,
    # so it is used as a fallback and flagged.
    unit = (unit_of.get(name) or "").upper()
    if not unit:
        unit = "PAIR" if re.search(r"\bPAIR\b", name.upper()) else \
               "SET" if re.search(r"\bSET\b", name.upper()) else "NOS"
        notes.append(f"unit '{unit}' inferred from the item name (no sale history)")

    list_rate = round(per_pc * (1.35 if p["lh"] else 1) * pack, 2)
    rows.append(dict(stock_item_name=name, list_rate=f"{list_rate:.2f}",
                     unit=unit, brand=DOC["brand"], doc_title=DOC["doc_title"],
                     effective_from=DOC["effective_from"], storage_path=DOC["storage_path"],
                     page_no=cell["page_no"], price_per_piece=f"{per_pc:.2f}", pack_qty=pack,
                     thread_form=cell["thread_form"], size=cell["size"], grade=cell["grade"],
                     edp_code="", confidence=conf, note=" | ".join(notes)))

with (HERE / "price_list_rows_v2.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
with (HERE / "price_list_skipped_v2.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["stock_item_name", "reason"]); w.writerows(skipped)

print(f"TOTEM item names scanned : {len(names):,}")
print(f"MATCHED -> price_list    : {len(rows):,}")
print(f"skipped                  : {len(skipped):,}")
for k, v in stats.most_common():
    print(f"   {v:>5}  {k}")
print("\nconfidence: " + ", ".join(f"{k}={v}" for k, v in Counter(r["confidence"] for r in rows).items()))
print("pages     : " + ", ".join(f"p{k}={v}" for k, v in sorted(Counter(r["page_no"] for r in rows).items())))
print(f"units missing: {sum(1 for r in rows if not r['unit'])}")
