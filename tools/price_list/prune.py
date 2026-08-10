"""Remove price_list rows whose item does not exist in THIS project's stock_items."""
import csv, json, pathlib, re, urllib.parse, urllib.request

HERE = pathlib.Path(__file__).parent
from _cfg import TEST as URL, TEST_KEY as KEY
H = {"apikey": KEY, "Authorization": "Bearer " + KEY}

def call(method, path, prefer=None):
    h = dict(H)
    if prefer: h["Prefer"] = prefer
    r = urllib.request.Request(f"{URL}/{path}", method=method, headers=h)
    with urllib.request.urlopen(r) as resp:
        return resp.read(), dict(resp.headers)

def page(path, **q):
    out, off = [], 0
    while True:
        qs = "&".join(f"{k}={v}" for k, v in q.items())
        b = json.loads(call("GET", f"{path}?{qs}&limit=1000&offset={off}")[0])
        out += b
        if len(b) < 1000:
            return out
        off += 1000

stock = {x["name"] for x in page("stock_items", select="name")}
seeded = [x["stock_item_name"] for x in page("price_list", select="stock_item_name")]
orphans = [n for n in seeded if n not in stock]
print(f"price_list rows {len(seeded)}, orphaned {len(orphans)}")

for n in orphans:
    call("DELETE", "price_list?stock_item_name=eq." + urllib.parse.quote(n, safe=""))

_, hd = call("GET", "price_list?select=stock_item_name&limit=1", prefer="count=exact")
print("after prune:", hd.get("Content-Range"))
left = [x["stock_item_name"] for x in page("price_list", select="stock_item_name")]
print("still orphaned:", sum(1 for n in left if n not in stock))
