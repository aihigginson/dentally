"""
dentally_probe_pagination.py -- read-only: detect Dentally's unstable-pagination bug across
the bulk-paged entities. Signal = DUPLICATE ids within a bounded page walk (unambiguous;
independent of sort field). Also reports backward page boundaries. Rate-aware.
Usage:  python API/dentally_probe_pagination.py
"""
import importlib.util
import os
import time
from collections import Counter
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
_s = importlib.util.spec_from_file_location(
    "dentally_creds_local", os.path.join(HERE, "dentally_creds.local.py"))
creds = importlib.util.module_from_spec(_s); _s.loader.exec_module(creds)
BASE = creds.DENTALLY_BASE.rstrip("/")
HEADERS = {"Authorization": "Bearer " + creds.DENTALLY_TOKEN, "Accept": "application/json"}

CAP = 60   # pages per entity (bounded)
# (endpoint, extra params) -- the plain bulk-paged transactional entities
ENTITIES = [
    ("patients", {}), ("invoices", {}), ("invoice_items", {}),
    ("payments", {}), ("treatment_plans", {}), ("treatment_plan_items", {}),
    ("recalls", {}), ("nhs_claims", {}), ("treatment_appointments", {}),
    ("patient_referrals", {}), ("patient_stats", {}),
]


def get(ep, pageno, params):
    for _ in range(6):
        r = requests.get(BASE + "/" + ep, headers=HEADERS,
                         params=dict(params, page=pageno, per_page=100), timeout=90)
        if r.status_code == 429:
            time.sleep(int(r.headers.get("RateLimit-Reset-After", 10)) + 1); continue
        r.raise_for_status()
        rem = r.headers.get("RateLimit-Remaining")
        j = r.json()
        rows = next((v for k, v in j.items() if k != "meta"), [])
        if isinstance(rows, dict):
            rows = [rows]
        meta = j.get("meta") or {}
        return rows, meta, (int(rem) if rem and str(rem).isdigit() else None)
    return [], {}, None


print("entity                  pages  rows   distinct  DUPS  back-bnds  total_pages")
print("-" * 78)
for ep, params in ENTITIES:
    ids, last_first, back = [], None, 0
    pg, total_pages = 1, None
    prev_last = None
    while pg <= CAP:
        rows, meta, rem = get(ep, pg, params)
        total_pages = meta.get("total_pages") or total_pages
        if not rows:
            break
        pags = [x.get("id") for x in rows if isinstance(x, dict)]
        if prev_last is not None and pags and isinstance(pags[0], int) and isinstance(prev_last, int) and pags[0] <= prev_last:
            back += 1
        prev_last = pags[-1] if pags else prev_last
        ids.extend(pags)
        if rem is not None and rem < 20:
            time.sleep(2)
        if len(rows) < 100:
            break
        pg += 1
    c = Counter(ids)
    dups = sum(1 for _, n in c.items() if n > 1)
    flag = "  <== BUG" if dups else ""
    print("%-22s %5d  %5d  %7d  %5d  %8d   %s%s"
          % (ep, pg if len(ids) else 0, len(ids), len(set(ids)), dups, back,
             total_pages or 0, flag))
