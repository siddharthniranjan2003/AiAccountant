"""Independent geometric read of the Silver Cut EDP grids (pages 12-28).

Each price is paired with the FAB code physically to its left, and each code column
is labelled by the grade header whose x-centre sits above it. This checks the part
of extract2.py that is hardest to get right: the block-index -> grade-list mapping.
"""
import re, sys
from geom import words, rows_of

FAB  = re.compile(r'^FAB\d+$')
NUM  = re.compile(r'^\d[\d,]*$')
CODE_TOK  = re.compile(r'^S[A-Z]{0,2}\d$')                       # SA1 SA3 SAF3 SBU3 SD1 SC4 ...
CONT_TOK  = re.compile(r'^(PM|P\d|TC|O/G|W/O|\((BRIGHT|TIN|TIALN|TICN)\))$')

def blocks(pg, W):
    rws = rows_of(W[pg])
    heads = [i for i, (y, r) in enumerate(rws) if any(w[4] == 'Code' for w in r)
             and any(w[4] == 'EDP' for w in r)]
    out = []
    for n, i in enumerate(heads):
        end = heads[n+1] if n+1 < len(heads) else len(rws)
        # grade header = nearest row above that is made of grade-ish tokens
        gh, best = None, 0
        for j in range(i-1, max(-1, i-8), -1):
            if any(FAB.match(w[4]) for w in rws[j][1]): continue
            n = sum(1 for w in rws[j][1] if CODE_TOK.match(w[4]))
            if n > best: gh, best = rws[j], n
        out.append((gh, rws[i], rws[i+1:end]))
    return out

def grade_cols(gh):
    """merge adjacent grade words into labels, return [(xcentre, label)]"""
    if not gh: return []
    ws = gh[1]; groups, cur = [], []
    for w in ws:
        if cur and w[0] - cur[-1][1] > 12: groups.append(cur); cur = []
        cur.append(w)
    if cur: groups.append(cur)
    out = []
    for g in groups:
        lab = " ".join(x[4] for x in g)
        if any(CODE_TOK.match(x[4]) for x in g):
            out.append(((g[0][0]+g[-1][1])/2, lab))
    return out

def build(path='bbox.xml'):
    W = words(path); cells = []
    for pg in range(12, 29):
        for gh, hdr, data in blocks(pg, W):
            gcols = grade_cols(gh)
            if not gcols: continue
            # margin = left edge of the size column: cluster label-token x over the block
            # and keep only clusters populated on most rows (markers appear on a few).
            nrow = sum(1 for y, r in data if any(FAB.match(w[4]) for w in r)) or 1
            labxs = []
            for y, r in data:
                cs = [w for w in r if FAB.match(w[4])]
                if not cs: continue
                labxs += [(w[0]+w[1])/2 for w in r if not FAB.match(w[4]) and (w[0]+w[1])/2 < min(c[0] for c in cs)]
            from geom import cluster as _cl
            keep = [c for c in _cl(labxs, 12) if sum(1 for x in labxs if abs(x-c) <= 12) >= 0.6*nrow]
            margin = (min(keep) - 12) if keep else 0
            size = pitch = ''
            for y, r in data:
                codes = [w for w in r if FAB.match(w[4])]
                if not codes: continue
                nums = [w for w in r if NUM.match(w[4])]
                # Each code's price is the nearest number to its right; those numbers are
                # then not available as size/pitch labels.
                price_of, taken = {}, set()
                for c in codes:
                    right = [n for n in nums if n[0] >= c[1] - 1 and id(n) not in taken]
                    if not right: continue
                    p = min(right, key=lambda n: n[0])
                    price_of[id(c)] = p; taken.add(id(p))
                # Walk left to right. Label tokens accumulate and are consumed by the next
                # code, so a second table further right picks up its OWN size, not the
                # left table's (pages 18/23/26 print two grids side by side). Tokens in the
                # far-left margin are standard markers (IS 6175, DIN 371) and are ignored.
                label = []
                for w in sorted(r, key=lambda a: a[0]):
                    xc = (w[0] + w[1]) / 2
                    if xc < margin or id(w) in taken: continue
                    if FAB.match(w[4]):
                        if label:
                            pitch = label[-1] if re.match(r'^([\d.]+|-)$', label[-1]) else ''
                            rest  = label[:-1] if pitch else label
                            size  = rest[-1] if rest else ''
                            label = []
                        p = price_of.get(id(w))
                        if p is None: continue
                        gx = min(gcols, key=lambda g: abs(g[0] - xc))
                        cells.append(dict(page_no=pg, size=size, pitch=pitch, grade=gx[1],
                                          edp_code=w[4], price=int(p[4].replace(',', ''))))
                    else:
                        label.append(w[4])
    return cells

if __name__ == '__main__':
    c = build()
    from collections import Counter
    print("geometric EDP cells:", len(c))
    print("pages:", dict(sorted(Counter(x['page_no'] for x in c).items())))
    print("grades:", len(set(x['grade'] for x in c)))
    for x in c[:4]: print("  ", x)
