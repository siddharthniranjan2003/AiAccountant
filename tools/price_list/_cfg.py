"""Supabase endpoints and keys, read from the gitignored env files.

Nothing secret lives in this directory. `.env` and `env/` are both gitignored, so
the scripts here resolve credentials at run time instead of carrying them.

  TEST  - the testing project, service-role key: full read/write.
  PROD  - the client's production project, publishable/anon key: READ ONLY.
          Item names and invoice history come from here; never write to it.
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]


def _from_dotenv():
    txt = (ROOT / ".env").read_text(encoding="utf-8")
    url = re.search(r"^SUPABASE_URL=(.+)$", txt, re.M).group(1).strip()
    key = re.search(r"^SUPABASE_SERVICE_KEY=(.+)$", txt, re.M).group(1).strip()
    return url, key


def _from_deployment():
    cfg = json.loads((ROOT / "env" / "deployment.json").read_text(encoding="utf-8"))
    return cfg["SUPABASE_URL"], cfg["SUPABASE_ANON_KEY"]


TEST_URL, TEST_KEY = _from_dotenv()
PROD_URL, PROD_KEY = _from_deployment()

TEST = TEST_URL + "/rest/v1"
PROD = PROD_URL + "/rest/v1"


def headers(key, **extra):
    return {"apikey": key, "Authorization": "Bearer " + key, **extra}
