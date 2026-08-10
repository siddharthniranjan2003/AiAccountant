"""Upload the source PDF to Supabase Storage so the band's download button works."""
import json, pathlib, re, urllib.error, urllib.request

from _cfg import TEST_URL as BASE, TEST_KEY as KEY
import sys
DEFAULT_PDF = r"D:\Downloads\TOTEM-HPT-HSS-TAPS-Price-list-Effective-01.01.2024_Gokul-Traders.pdf"
PDF = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PDF
PDF = pathlib.Path(PDF)
OBJ = "price-lists/totem-hpt-2024-01-08.pdf"

def req(method, path, data=None, ctype="application/json"):
    r = urllib.request.Request(f"{BASE}{path}", method=method, data=data,
        headers={"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": ctype})
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, resp.read().decode()[:300]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]

print("create bucket :", req("POST", "/storage/v1/bucket",
      json.dumps({"id": "price-lists", "name": "price-lists", "public": True}).encode()))

blob = PDF.read_bytes()
print(f"pdf size      : {len(blob):,} bytes")
print("upload        :", req("POST", f"/storage/v1/object/{OBJ}", blob, "application/pdf"))

url = f"{BASE}/storage/v1/object/public/{OBJ}"
try:
    with urllib.request.urlopen(url) as r:
        print(f"public fetch  : {r.status}, {len(r.read()):,} bytes")
        print(f"public URL    : {url}")
except urllib.error.HTTPError as e:
    print("public fetch  :", e.code, e.read().decode()[:200])
