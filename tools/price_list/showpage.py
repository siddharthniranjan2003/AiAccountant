import sys, pathlib
pages = (pathlib.Path(__file__).parent / "pages.txt").read_text(encoding="utf-8", errors="replace").split("\f")
for spec in sys.argv[1:]:
    n, _, cap = spec.partition(":")
    cap = int(cap) if cap else 34
    lines = [l.rstrip() for l in pages[int(n) - 1].splitlines() if l.strip()]
    print(f"\n{'='*100}\nPAGE {n}   ({len(lines)} non-blank lines, showing {min(cap,len(lines))})\n{'='*100}")
    for l in lines[:cap]:
        print(l[:150])
