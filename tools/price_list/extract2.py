"""Parser v2 - block aware. Emits the full catalogue to price_list_items.csv."""
import csv, pathlib, re

HERE = pathlib.Path(__file__).parent
pages = (HERE / "pages.txt").read_text(encoding="utf-8", errors="replace").split("\f")

HSS, GOLD, HSSE, SC = ("HSS Hand / Short Machine / Long Shank",
                       "TOTEM GOLD (TiN coated)", "High Performance Taps HSSE", "TOTEM Silver Cut")

# ---- positional pages: (series, standard, size_system, [(thread, grade), ...]) keyed by ncols
POS = {
 (3, 9): (HSS, "BS-949 / ANSI", "inch", [("BSW/BSF","Standard"),("BSW/BSF","SF/RS"),("BSW/BSF","SPPT"),
          ("UNF/UNC","Standard"),("UNF/UNC","SF/RS"),("UNF/UNC","SPPT"),
          ("BSP","Standard"),("BSPT","Standard"),("NPT","Standard")]),
 (4, 5): (HSS, "IS-6175", "metric", [("Metric Coarse","Standard"),("Metric Coarse","SF/RS"),
          ("Metric Coarse","SPPT"),("Metric Coarse","Long Shank A/C/D"),("Metric Coarse","Long Shank B (SPPT)")]),
 (5, 5): (HSS, "IS-6175", "metric", [("Metric Coarse","Standard"),("Metric Coarse","SF/RS"),
          ("Metric Coarse","SPPT"),("Metric Coarse","Long Shank A/C/D"),("Metric Coarse","Long Shank B (SPPT)")]),
 (6, 3): (HSS, "BS-949", "inch", [("BSB","Standard"),("BSW","Long Shank A/C/D"),("BSW","Long Shank B (SPPT)")]),
 (8, 5): (GOLD, "BS-949 / ANSI", "inch", [("BSW/BSF/UNC/UNF","STD GOLD"),("BSW/BSF/UNC/UNF","SPPT GOLD"),
          ("BSP","STD GOLD"),("BSPT","STD GOLD"),("NPT","STD GOLD")]),
 (9, 4): (GOLD, "IS-6175", "metric", [("Metric Coarse","STD GOLD"),("Metric Coarse","SPPT GOLD"),
          ("Metric Coarse","Long Shank A/C/D GOLD"),("Metric Coarse","Long Shank B GOLD")]),
 (10,4): (GOLD, "IS-6175", "metric", [("Metric Coarse","STD GOLD"),("Metric Coarse","SPPT GOLD"),
          ("Metric Coarse","Long Shank A/C/D GOLD"),("Metric Coarse","Long Shank B GOLD")]),
 (11,10):(HSSE, "IS-6175 / BS-949", "metric", [("Metric","SPIREX Bright"),("Metric","SPIREX Gold"),
          ("Metric","STD XL Bright"),("Metric","STD XL Gold"),("Metric","SPPT XL Bright"),("Metric","SPPT XL Gold"),
          ("Metric","LS 'C' XL Bright"),("Metric","LS 'C' XL Gold"),("Metric","LS 'B' XL Bright"),("Metric","LS 'B' XL Gold")]),
}

# ---- EDP pages: ordered list of blocks, each a grade list
EDP = {
 12: ("metric", [["SA1 (BRIGHT)","SA3 (TIN)","SA4 (TIALN)","SAF3 (TIN)","SAF5 (TICN)"]]),
 13: ("metric", [["SA1 (BRIGHT)","SA3 (TIN)","SA4 (TIALN)","SAF3 (TIN)","SAF5 (TICN)"]]),
 14: ("mixed",  [["SAF5 PM (TICN)","SAH4 PM (TIALN)"],["SAF5 PM (TICN)","SAH4 PM (TIALN)"],
                 ["SA1 (BRIGHT)","SA3 (TIN)","SA4 (TIALN)"]]),
 15: ("UNF/UNC",[["SA1 (BRIGHT)","SA3 (TIN)","SA4 (TIALN)"]]*3),
 16: ("metric", [["SB1 (BRIGHT)","SB3 (TIN)","SB4 (TIALN)","SBF3 (TIN)","SBF5 (TICN)"]]),
 17: ("metric", [["SB1 (BRIGHT)","SB3 (TIN)","SB4 (TIALN)","SBF3 (TIN)","SBF5 (TICN)"]]),
 18: ("UNF/UNC",[["SBU3 (TIN)","SBU5 (TICN)","SBF5 P3 (TICN)"],["SBU3 (TIN)","SBU5 (TICN)"]]),
 19: ("UNC",    [["SB1 (BRIGHT)","SB3 (TIN)","SBU3 (TIN)"]]*2),
 20: ("UNC",    [["SB1 (BRIGHT)","SB3 (TIN)","SBU3 (TIN)","SBU5 (TICN)"]]*2),
 21: ("metric", [["SC3 (TIN)","SC4 (TIALN)","SCF3 (TIN)","SCF5 (TICN)"]]),
 22: ("metric", [["SC3 (TIN)","SC4 (TIALN)","SCF3 (TIN)","SCF5 (TICN)","SC4 TC"]]),
 23: ("mixed",  [["SC4 PM (TIALN)"],["SC3 (TIN)","SC4 (TIALN)"],["SC3 (TIN)","SC4 (TIALN)"]]),
 24: ("metric", [["SD1 O/G (BRIGHT)","SD3 O/G (TIN)","SD5 O/G (TICN)","SD1 W/O O/G (BRIGHT)","SD3 W/O O/G (TIN)"]]*2),
 25: ("metric", [["SAS3 (TIN)","SAS5 (TICN)","SAI4 (TIALN)","SBS5 (TICN)","SBI4 (TIALN)"]]*2),
 26: ("mixed",  [["SBS5 PM (TICN)"],["SAS3 (TIN)","SAS5 (TICN)","SBS5 (TICN)"],
                 ["SAS3 (TIN)","SAS5 (TICN)","SBS5 (TICN)"]]),
 27: ("mixed",  [["SAS3 (TIN)","SAS5 (TICN)","SBS5 (TICN)"],["SAS3 (TIN)","SAS5 (TICN)","SBS5 (TICN)"],
                 ["SA1 (BRIGHT)","SA3 (TIN)","SB1 (BRIGHT)","SB3 (TIN)","SC4 (TIALN)"]]),
 28: ("BSP",    [["SA3 (TIN)","SB3 (TIN)","SC4 (TIALN)"],["SA3 (TIN)"]]),
}

FAB, NUM = re.compile(r"^FAB\d+$"), re.compile(r"^\d{2,6}$")
VAL = re.compile(r"^(?:\d{2,6}|-|‐|–)$")
FLAG = re.compile(r"[#~*]")
STD = re.compile(r"\b(DIN\s*\d+|ISO\s*Part\s*\d+|IS[- ]?\d+|BS[- ]?\d+)\b", re.I)

rows, notes = [], []
def emit(**kw):
    kw.setdefault("edp_code", ""); kw.setdefault("moq_flag", ""); kw.setdefault("pitch_or_tpi", "")
    kw.setdefault("source_note", ""); kw.setdefault("standard", "")
    rows.append(kw)

def clean(t): return t.replace(",", "").strip()

# ------------------------------------------------------------------ EDP pages
for pg, (thread, blocks) in EDP.items():
    lines = pages[pg-1].splitlines()
    bi, std = -1, ""
    for raw in lines:
        if "EDP Code" in raw:
            bi += 1; continue
        m = STD.search(raw)
        if m and not FAB.search(raw):
            std = m.group(1)
        toks = raw.split()
        if bi < 0 or not any(FAB.match(t) for t in toks):
            continue
        grades = blocks[min(bi, len(blocks)-1)]
        label, col, i = [], 0, 0
        while i < len(toks):
            t = toks[i]
            if FAB.match(t) and i+1 < len(toks) and NUM.match(clean(toks[i+1])):
                if label:
                    parts = [p for p in label if not STD.fullmatch(p)]
                    # Standard markers (IS 6175, DIN 371, ISO Part 2, LONG SHANK TAPS)
                    # are printed in the left margin and share a line with real data.
                    # Taking parts[0] made 55 cells "size=IS pitch=6175". Size and pitch
                    # are the two tokens nearest the first EDP code, so read from the right.
                    pitch = parts[-1] if parts and re.fullmatch(r"[\d.]+|-", parts[-1]) else ""
                    rest  = parts[:-1] if pitch else parts
                    size  = rest[-1] if rest else ""
                    col = 0
                if col < len(grades):
                    emit(page_no=pg, series=SC, standard=std, thread_form=thread,
                         size=size, size_system=("metric" if size.upper().startswith("M") else "inch"),
                         pitch_or_tpi=pitch, grade=grades[col], edp_code=t,
                         price_per_piece=clean(toks[i+1]))
                col += 1; label = []; i += 2
            else:
                label.append(t); i += 1

# ------------------------------------------------------------ positional pages
for pg in [3,4,5,6,8,9,10,11]:
    lines = pages[pg-1].splitlines()
    # p6 carries a second "SPECIAL PITCH TAPS" grid whose Pitch column ("40, 48")
    # looks like two extra price cells. Stop the positional pass at that header;
    # the special-pitch rows are parsed on their own below.
    cut = next((i for i, l in enumerate(lines) if "SPECIAL PITCH" in l.upper()), len(lines))
    for raw in lines[:cut]:
        toks = [clean(t) for t in raw.split()]
        if len(toks) < 3: continue
        k = 0
        while k < len(toks) and VAL.match(toks[len(toks)-1-k]): k += 1
        spec = POS.get((pg, k))
        if not spec: continue
        head = " ".join(toks[:len(toks)-k])
        if not re.search(r"\d", head) or STD.search(head): continue
        series, standard, syst, cols = spec
        flag = "".join(sorted(set(FLAG.findall(head))))
        size = FLAG.sub("", head).strip()
        # A bare 1-2 digit label is a BA/screw *number*, not an inch size - those
        # rows belong to the side-by-side number tables and are parsed separately.
        # Without this guard they get read as inch rows and overwrite real prices.
        if syst == "inch" and re.fullmatch(r"\d{1,2}", size):
            continue
        for (thread, grade), v in zip(cols, toks[len(toks)-k:]):
            if NUM.match(v):
                emit(page_no=pg, series=series, standard=standard, thread_form=thread,
                     size=size, size_system=syst, grade=grade, price_per_piece=v, moq_flag=flag)

# ---------------------------------------- p3 BA / UNF number tables (side by side)
BA_COLS = [("BA","Standard"),("BA","SPPT"),("UNF/UNC","Standard"),("UNF/UNC","SPPT")]
for raw in pages[2].splitlines():
    toks = [clean(t) for t in raw.split()]
    if len(toks) not in (5, 10) or not re.fullmatch(r"\d{1,2}", toks[0]): continue
    for half in ([toks[:5], toks[5:]] if len(toks) == 10 else [toks]):
        if not re.fullmatch(r"\d{1,2}", half[0]): continue
        for (thread, grade), v in zip(BA_COLS, half[1:]):
            if NUM.match(v):
                emit(page_no=3, series=HSS, standard="BS-949", thread_form=thread,
                     size=half[0], size_system="number", grade=grade, price_per_piece=v)

# ---------------------------------------- p6 special pitch table (1 price column)
for raw in pages[5].splitlines():
    toks = raw.split()
    if len(toks) < 3 or not FLAG.search(toks[0]): continue
    if not NUM.match(clean(toks[-1])): continue
    emit(page_no=6, series=HSS, standard="BS-949 Special Pitch", thread_form="Special Pitch",
         size=FLAG.sub("", toks[0]).strip(), size_system="inch",
         pitch_or_tpi=" ".join(toks[1:-1]).replace(",", ", "),
         grade="Standard", price_per_piece=clean(toks[-1]), moq_flag="*")

# ---------------------------------------- flag the source-document defect on p14
bad = 0
for r in rows:
    if r["page_no"] == 14 and r["size_system"] == "metric" and r["pitch_or_tpi"] in {"20","18","16","14","13","11","10","9","8"}:
        r["source_note"] = "PDF defect: Pitch column on p14 table 1 duplicates the UNC TPI values; pitch not trustworthy"
        bad += 1

out = HERE / "price_list_items.csv"
cols = ["page_no","series","standard","thread_form","size","size_system","pitch_or_tpi",
        "grade","edp_code","price_per_piece","moq_flag","source_note"]
with out.open("w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(rows)

from collections import Counter
per = Counter(r["page_no"] for r in rows)
print("  " + "  ".join(f"p{p}:{per[p]}" for p in sorted(per)))
print(f"\nTOTAL {len(rows):,} price rows  ({len(per)} pages)")
print(f"flagged with the p14 pitch defect: {bad}")
