"""Dump the header block of every price-grid page so column specs can be written."""
import pathlib, re
pages = (pathlib.Path(__file__).parent / "pages.txt").read_text(encoding="utf-8", errors="replace").split("\f")
GRIDS = [3,4,5,6,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29]
DATA = re.compile(r"(FAB\d+|\s\d{3,6}\s|\s-\s)")
for n in GRIDS:
    lines = [l.rstrip() for l in pages[n-1].splitlines() if l.strip()]
    # header = lines before the first line that looks like data (has 2+ price-ish cells)
    hdr = []
    for l in lines:
        if len(DATA.findall(l)) >= 3:
            break
        hdr.append(l)
    print(f"\n--- p{n} " + "-"*88)
    for l in hdr[:7]:
        print("   " + re.sub(r"\s{2,}", " | ", l.strip())[:145])
