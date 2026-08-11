"""Independent geometric catalogue of the TOTEM price grids.

Prices are located by the x-position of each printed number relative to the
column its header sits over, NOT by counting trailing tokens as extract2.py does.
Column specs below were each confirmed against the rendered page image.
"""
import re, sys
from geom import words, rows_of, cluster, isval

MC = "Metric Coarse"
SPEC = {
 (3,'A'): dict(y=(180,545), n=9, cols=[("BSW/BSF","Standard"),("BSW/BSF","SF/RS"),("BSW/BSF","SPPT"),
        ("UNF/UNC","Standard"),("UNF/UNC","SF/RS"),("UNF/UNC","SPPT"),
        ("BSP","Standard"),("BSPT","Standard"),("NPT","Standard")], sys_="inch"),
 (4,'A'): dict(y=(170,800), n=5, cols=[(MC,"Standard"),(MC,"SF/RS"),(MC,"SPPT"),
        (MC,"Long Shank A/C/D"),(MC,"Long Shank B (SPPT)")], sys_="metric"),
 (5,'A'): dict(y=(170,800), n=5, cols=[(MC,"Standard"),(MC,"SF/RS"),(MC,"SPPT"),
        (MC,"Long Shank A/C/D"),(MC,"Long Shank B (SPPT)")], sys_="metric"),
 (6,'A'): dict(y=(200,460), n=3, cols=[("BSB","Standard"),("BSW","Long Shank A/C/D"),
        ("BSW","Long Shank B (SPPT)")], sys_="inch"),
 (8,'A'): dict(y=(170,800), n=5, cols=[("BSW/BSF/UNC/UNF","STD GOLD"),("BSW/BSF/UNC/UNF","SPPT GOLD"),
        ("BSP","STD GOLD"),("BSPT","STD GOLD"),("NPT","STD GOLD")], sys_="inch"),
 (9,'A'): dict(y=(170,800), n=4, cols=[(MC,"STD GOLD"),(MC,"SPPT GOLD"),
        (MC,"Long Shank A/C/D GOLD"),(MC,"Long Shank B GOLD")], sys_="metric"),
 (10,'A'):dict(y=(170,800), n=4, cols=[(MC,"STD GOLD"),(MC,"SPPT GOLD"),
        (MC,"Long Shank A/C/D GOLD"),(MC,"Long Shank B GOLD")], sys_="metric"),
 (11,'A'):dict(y=(170,800), n=10, cols=[("Metric","SPIREX Bright"),("Metric","SPIREX Gold"),
        ("Metric","STD XL Bright"),("Metric","STD XL Gold"),("Metric","SPPT XL Bright"),
        ("Metric","SPPT XL Gold"),("Metric","LS 'C' XL Bright"),("Metric","LS 'C' XL Gold"),
        ("Metric","LS 'B' XL Bright"),("Metric","LS 'B' XL Gold")], sys_="metric"),
}
# page 3 lower half: two side-by-side BA / UNF-UNC "Number" tables.
# The printed header rule puts BA over three sub-columns, but the sub-headers read
# Standard,SPPT,Standard,SPPT -- two 2-column groups. Published-PDF defect; 2+2 is used.
NUMTAB = dict(y=(650,760), label_x=[62,330], price_x=[[113,164,215,266],[381,432,483,534]],
              cols=[("BA","Standard"),("BA","SPPT"),("UNF/UNC","Standard"),("UNF/UNC","SPPT")])

FLAG = re.compile(r"[#~*‐–—]")
def norm(s):
    s = FLAG.sub("", str(s)).upper().replace("”", '"').strip()
    return re.sub(r"\s+", "", s)

def build(path="bbox.xml"):
    W = words(path); cells = {}
    def put(pg, thread, size, grade, val, sys_, note=""):
        cells.setdefault((pg, thread, norm(size), grade), (int(val), size, sys_, note))
    for (pg, blk), sp in SPEC.items():
        lo, hi = sp["y"]
        rws = [(y, r) for y, r in rows_of(W[pg]) if lo <= y <= hi]
        xs = [(w[0]+w[1])/2 for y, r in rws for w in r if isval(w[4])]
        cl = [c for c in cluster(xs)
              if sum(1 for y, r in rws for w in r if isval(w[4]) and abs((w[0]+w[1])/2-c) <= 14) >= 0.30*len(rws)]
        if len(cl) != sp["n"]:
            print(f"  !! page {pg}{blk}: found {len(cl)} columns, spec says {sp['n']} -> {[round(c) for c in cl]}", file=sys.stderr)
            continue
        left = min(cl) - 18
        for y, r in rws:
            lab = " ".join(w[4] for w in r if (w[0]+w[1])/2 < left).strip()
            if not lab: continue
            for w in r:
                xc = (w[0]+w[1])/2
                if xc < left or not isval(w[4]) or not w[4][0].isdigit(): continue
                i = min(range(len(cl)), key=lambda j: abs(cl[j]-xc))
                if abs(cl[i]-xc) > 18: continue
                th, gr = sp["cols"][i]
                put(pg, th, lab, gr, w[4].replace(",", ""), sp["sys_"])
    # page 6 lower half: SPECIAL PITCH TAPS - size, pitch(es), one price column
    for y, r in rows_of(W[6]):
        if not (560 <= y <= 720): continue
        lab = next((w[4] for w in r if abs((w[0]+w[1])/2 - 124) <= 14), None)
        val = next((w[4] for w in r if abs((w[0]+w[1])/2 - 471) <= 14 and w[4].replace(",", "").isdigit()), None)
        if lab and val:
            put(6, "Special Pitch", lab, "Standard", val.replace(",", ""), "inch")

    # page 3 number tables
    lo, hi = NUMTAB["y"]
    for y, r in rows_of(W[3]):
        if not (lo <= y <= hi): continue
        for lx, pxs in zip(NUMTAB["label_x"], NUMTAB["price_x"]):
            lab = next((w[4] for w in r if abs((w[0]+w[1])/2-lx) <= 12), None)
            if lab is None: continue
            for i, px in enumerate(pxs):
                v = next((w[4] for w in r if abs((w[0]+w[1])/2-px) <= 12 and isval(w[4])), None)
                if v and v[0].isdigit():
                    th, gr = NUMTAB["cols"][i]
                    put(3, th, lab, gr, v.replace(",", ""), "number",
                        "PDF defect: BA/UNF-UNC header rule spans 3 columns; read as two 2-column groups")
    return cells

if __name__ == "__main__":
    c = build()
    from collections import Counter
    print(f"geometric catalogue cells: {len(c)}")
    print("per page:", dict(sorted(Counter(k[0] for k in c).items())))
    print("sample :", c[(3,"BSP",'1.1/2"',"Standard")])
