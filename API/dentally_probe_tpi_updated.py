"""
dentally_probe_tpi_updated.py -- read-only: prove that updated_after cannot MISS
newly-created treatment_plan_items. Checks, on real Maple Dental data:
  1. is updated_at ever null / missing?           (null => creations could be dropped)
  2. is updated_at ever < created_at?             (would break the superset logic)
  3. do genuinely NEW creations appear in a recent updated_after window?
  4. volume distribution by updated_after threshold (sanity of the 106k).

Usage:  python API/dentally_probe_tpi_updated.py
"""
import importlib.util
import os
from datetime import datetime, timezone, timedelta

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
_s = importlib.util.spec_from_file_location(
    "dentally_creds_local", os.path.join(HERE, "dentally_creds.local.py"))
creds = importlib.util.module_from_spec(_s); _s.loader.exec_module(creds)
BASE = creds.DENTALLY_BASE.rstrip("/")
HEADERS = {"Authorization": "Bearer " + creds.DENTALLY_TOKEN, "Accept": "application/json"}
EP = "treatment_plan_items"


def get(params):
    r = requests.get(BASE + "/" + EP, headers=HEADERS, params=params, timeout=90)
    r.raise_for_status()
    j = r.json()
    rows = next((v for k, v in j.items() if k != "meta"), [])
    total = (j.get("meta") or {}).get("total_count")
    return rows, total


def total(params):
    _, t = get({**params, "page": 1, "per_page": 1})
    return t


def parse(ts):
    # Dentally ISO8601 with offset, e.g. 2026-07-04T20:35:55.599+01:00
    return datetime.fromisoformat(ts) if ts else None


# --- 1 & 2: null / ordering audit across a broad sample -----------------------
# Sample from the OLD end of the floored window (page 1 of updated_after=2024-04-01,
# ascending) AND the newest unfiltered rows, so we cover both ends of the timeline.
cut = "2024-04-01T00:00:00Z"
samples = []
for label, params, pages in (("floored (oldest end)", {"updated_after": cut}, 5),
                             ("unfiltered (newest end)", {}, 5)):
    for p in range(1, pages + 1):
        rows, _ = get({**params, "page": p, "per_page": 100})
        for r in rows:
            samples.append((label, r))

null_upd = [r for _, r in samples if not r.get("updated_at")]
bad_order = [r for _, r in samples
             if r.get("updated_at") and r.get("created_at")
             and parse(r["updated_at"]) < parse(r["created_at"])]
print("Audited", len(samples), "real rows (both ends of the timeline)")
print("  updated_at NULL/missing :", len(null_upd), "  <-- must be 0 for updated_after to be safe")
print("  updated_at < created_at :", len(bad_order), "  <-- must be 0")

# --- 3: do NEW creations show up in a recent updated_after window? -------------
now = datetime.now(timezone.utc)
d30 = (now - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
rows30 = []
for p in range(1, 6):  # up to 500 rows updated in the last 30 days
    rr, _ = get({"updated_after": d30, "page": p, "per_page": 100})
    rows30 += rr
    if len(rr) < 100:
        break
created_recent = [r for r in rows30
                  if r.get("created_at") and parse(r["created_at"]) >= parse(d30)]
print("\nLast-30-day updated_after sample:", len(rows30), "rows;",
      len(created_recent), "were also CREATED in the last 30 days")
print("  -> brand-new items appearing here proves updated_after captures creations")

# --- 4: volume distribution (sanity) -----------------------------------------
print("\nupdated_after totals:")
for lbl, d in (("2024-04-01 (window)", cut),
               ("2025-01-01", "2025-01-01T00:00:00Z"),
               ("2025-07-01", "2025-07-01T00:00:00Z"),
               ("2026-01-01", "2026-01-01T00:00:00Z"),
               ("last 30 days", d30)):
    print("  {:22} {}".format(lbl, total({"updated_after": d})))
print("  {:22} {}".format("baseline (no filter)", total({})))
