"""How many distinct tables (by column count) live on each positional page?"""
import pathlib, re
from collections import Counter
pages = (pathlib.Path(__file__).parent / "pages.txt").read_text(encoding="utf-8", errors="replace").split("\f")
VAL = re.compile(r"^(?:\d{2,6}|-|‐|–)$")

for pg in [3,4,5,6,8,9,10,11,29]:
    counts = Counter()
    samples = {}
    for raw in pages[pg-1].splitlines():
        toks = [t.replace(",", "") for t in raw.split()]
        if len(toks) < 3:
            continue
        k = 0
        while k < len(toks) and VAL.match(toks[len(toks)-1-k]):
            k += 1
        head = " ".join(toks[:len(toks)-k])
        if k >= 2 and re.search(r"\d", head):
            counts[k] += 1
            samples.setdefault(k, raw.strip()[:118])
    print(f"\np{pg}: " + ", ".join(f"{n} cols x{c} rows" for n, c in sorted(counts.items(), reverse=True)))
    for n, s in sorted(samples.items(), reverse=True):
        print(f"    [{n}] {s}")
