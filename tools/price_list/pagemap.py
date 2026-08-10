"""Phase 1 step 1: classify all 36 pages as price grid / technical chart / other."""
import re, subprocess, pathlib

import sys
DEFAULT_PDF = r"D:\Downloads\TOTEM-HPT-HSS-TAPS-Price-list-Effective-01.01.2024_Gokul-Traders.pdf"
PDF = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PDF
OUT = pathlib.Path(__file__).parent / "pages.txt"
subprocess.run(["pdftotext", "-layout", PDF, str(OUT)], check=True)
pages = OUT.read_text(encoding="utf-8", errors="replace").split("\f")

PRICE_HDR = re.compile(r"Each\s*₹|Price\s*₹|EDP Code|RATES ARE IN RUPEES", re.I)
MONEY = re.compile(r"(?<![\d.])\d{3,6}(?![\d.])")     # 3-6 digit integers = rupee cells
SPEC  = re.compile(r"Drill Size|Tapping|Nominal Diameter|TPI\b.*Drill|Thread form", re.I)

rows = []
for i, txt in enumerate(pages, 1):
    if not txt.strip():
        continue
    money = len(MONEY.findall(txt))
    has_hdr = bool(PRICE_HDR.search(txt))
    is_spec = bool(SPEC.search(txt))
    if has_hdr and money >= 25:
        kind = "PRICE GRID"
    elif is_spec and money >= 15:
        kind = "technical chart"
    elif money >= 25:
        kind = "PRICE GRID?"
    else:
        kind = "front/back matter"
    title = next((l.strip() for l in txt.splitlines() if len(l.strip()) > 12), "")[:52]
    rows.append((i, kind, money, title))

w = max(len(r[1]) for r in rows)
print(f"{'pg':>3}  {'kind':<{w}}  {'$cells':>6}  first line")
print("-" * 96)
for i, kind, money, title in rows:
    print(f"{i:>3}  {kind:<{w}}  {money:>6}  {title}")

grids = [r for r in rows if r[1].startswith("PRICE GRID")]
print(f"\nprice grids: {len(grids)} pages -> {[r[0] for r in grids]}")
print(f"rupee cells on those pages (upper bound on catalogue rows): {sum(r[2] for r in grids):,}")
