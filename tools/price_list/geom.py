"""Geometric re-extraction of the TOTEM positional price grids from word bboxes.
Independent of extract2.py: columns come from the printed 'Each Rs' anchors and the
header rows above them, not from counting trailing tokens."""
import xml.etree.ElementTree as ET, gzip, pathlib, re, sys
NS = '{http://www.w3.org/1999/xhtml}'
HERE = pathlib.Path(__file__).parent

def _open(path):
    """bbox.xml if present, else the committed bbox.xml.gz."""
    p = pathlib.Path(path)
    if not p.is_absolute(): p = HERE / p
    if p.exists(): return p.open('rb')
    gz = p.with_suffix(p.suffix + '.gz')
    if gz.exists(): return gzip.open(gz, 'rb')
    raise FileNotFoundError(f"{p} (and no .gz beside it); "
                            f"regenerate with: pdftotext -bbox-layout <pdf> {p.name}")

def words(path='bbox.xml'):
    out = {}
    for i, p in enumerate(ET.parse(_open(path)).getroot().iter(NS+'page'), 1):
        ws = [(float(w.get('xMin')), float(w.get('xMax')), float(w.get('yMin')),
               float(w.get('yMax')), (w.text or '')) for w in p.iter(NS+'word')]
        out[i] = ws
    return out

def rows_of(ws, tol=3.0):
    """group words into visual rows by yMin"""
    ws = sorted(ws, key=lambda w: (w[2], w[0]))
    rows, cur, y = [], [], None
    for w in ws:
        if y is None or abs(w[2]-y) <= tol:
            cur.append(w); y = w[2] if y is None else y
        else:
            rows.append((y, sorted(cur, key=lambda a: a[0]))); cur=[w]; y=w[2]
    if cur: rows.append((y, sorted(cur, key=lambda a: a[0])))
    return rows

def col_anchors(rws):
    """x-centres of every 'Each' marker == one price column"""
    for y, r in rws:
        eaches = [w for w in r if w[4] == 'Each']
        if len(eaches) >= 3:
            return y, [ (w[0]+w[1])/2 for w in eaches ]
    return None, []

def span_label(rws, ytarget, lo, hi):
    """concatenate words on row ytarget whose x-centre falls in [lo,hi]"""
    for y, r in rws:
        if abs(y-ytarget) < 0.5:
            return ' '.join(w[4] for w in r if lo <= (w[0]+w[1])/2 <= hi).strip()
    return ''

NUMRE  = re.compile(r'^\d[\d,]*$')
DASHRE = re.compile(r'^[-‐–—]$')
def isnum(t):  return bool(NUMRE.match(t))
def isval(t):  return isnum(t) or bool(DASHRE.match(t))

def cluster(xs, tol=14.0):
    xs = sorted(xs); cs = []
    for x in xs:
        if cs and x - cs[-1][-1] <= tol: cs[-1].append(x)
        else: cs.append([x])
    return [sum(c)/len(c) for c in cs]

SIZE = re.compile(r"^(#|\*|~)?\s*(\d[\d./]*\s*(X|x)\s*[\d./]+|\d+[\d/.]*\"?|M\d+)")
FOOT = re.compile(r"nos|Minimum|Sizes|Only|Order|NOTE|Note", re.I)

def grid(ws):
    """-> (col_x[], [(y, size_label, {col_idx: token})]) purely from word geometry."""
    rws = rows_of(ws)
    # data rows: leftmost text looks like a size and the row carries >=2 value tokens
    data = []
    for y, r in rws:
        vals = [w for w in r if isval(w[4])]
        txt  = " ".join(w[4] for w in r)
        if len(vals) >= 2 and SIZE.match(txt) and not FOOT.search(txt):
            data.append((y, r))
    if not data: return [], []
    xs = [(w[0]+w[1])/2 for y, r in data for w in r if isval(w[4])]
    cols = [c for c in cluster(xs)
            if sum(1 for y, r in data for w in r
                   if isval(w[4]) and abs((w[0]+w[1])/2 - c) <= 14) >= 0.30*len(data)]
    if not cols: return [], []
    left = min(cols) - 18
    out = []
    for y, r in data:
        lab = " ".join(w[4] for w in r if (w[0]+w[1])/2 < left).strip()
        cells = {}
        for w in r:
            xc = (w[0]+w[1])/2
            if xc < left or not isval(w[4]): continue
            i = min(range(len(cols)), key=lambda j: abs(cols[j]-xc))
            if abs(cols[i]-xc) <= 18: cells[i] = w[4].replace(",", "")
        if lab and cells: out.append((y, lab, cells))
    return cols, out
