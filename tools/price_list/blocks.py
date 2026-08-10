import pathlib, re
pages = (pathlib.Path(__file__).parent / "pages.txt").read_text(encoding="utf-8", errors="replace").split("\f")
GR = re.compile(r"S[A-Z]{1,2}\d+(?:\s+(?:PM|P3|TC))?(?:\s+(?:W/O\s+)?O/G)?(?:\s*\([A-Z0-9]+\))?")
for pg in range(12, 29):
    lines = pages[pg-1].splitlines()
    nblocks = sum(1 for l in lines if "EDP Code" in l)
    print(f"p{pg}: {nblocks} 'EDP Code' header lines")
    for l in lines:
        g = [m.group(0).strip() for m in GR.finditer(l) if "(" in m.group(0) or "TC" in m.group(0)]
        if g:
            print("     grades:", " | ".join(dict.fromkeys(g)))
