"""Endpoints and keys for the v2 pipeline.

v2 reads names, reads sale history and writes rows all against the SAME project,
so a seeded row can never reference an item that does not exist there. That project
is the one in .env (testing), which is the only one with a service key.

Nothing secret lives here; .env is gitignored.
"""
import json, pathlib, re, ssl, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
_env = (ROOT / ".env").read_text(encoding="utf-8")

URL = re.search(r'"SUPABASE_URL"\s*:\s*"([^"]+)"', _env).group(1)
KEY = re.search(r'service_key"?\s*:\s*"([^"]+)"', _env).group(1)
REST = URL + "/rest/v1"

try:                                    # python.org builds ship without CA certs
    import certifi
    CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    CTX = ssl.create_default_context()


def _req(url, method="GET", body=None, extra=None):
    h = {"apikey": KEY, "Authorization": "Bearer " + KEY,
         "Content-Type": "application/json"}
    if extra: h.update(extra)
    data = json.dumps(body).encode() if body is not None else None
    return urllib.request.Request(url, data=data, headers=h, method=method)


def page(path, **q):
    """GET every row of a table, 1000 at a time."""
    out, off = [], 0
    while True:
        qs = "&".join(f"{k}={v}" for k, v in q.items())
        r = urllib.request.urlopen(
            _req(f"{REST}/{path}?{qs}&limit=1000&offset={off}"), context=CTX)
        b = json.load(r)
        out += b
        if len(b) < 1000:
            return out
        off += 1000


def send(path, body, method="POST", extra=None):
    r = urllib.request.urlopen(_req(f"{REST}/{path}", method, body, extra), context=CTX)
    return r.status, r.read().decode()[:400]
