"""
dentally_probe_tpi_window.py -- read-only: find a working date filter for
treatment_plan_items (and treatment_plans) and measure how much a 2024-04-01
cutoff shrinks the pull. Temporary; safe to delete after.

Usage:  python API/dentally_probe_tpi_window.py
"""
import importlib.util
import os

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
_s = importlib.util.spec_from_file_location(
    "dentally_creds_local", os.path.join(HERE, "dentally_creds.local.py"))
creds = importlib.util.module_from_spec(_s); _s.loader.exec_module(creds)
BASE = creds.DENTALLY_BASE.rstrip("/")
HEADERS = {"Authorization": "Bearer " + creds.DENTALLY_TOKEN, "Accept": "application/json"}

CUT = "2024-04-01T00:00:00Z"

# Candidate date-filter params to try (first that both 200s AND reduces the count wins).
CANDIDATES = [
    {},                                   # baseline (no filter) -> total
    {"updated_after": CUT},
    {"created_after": CUT},
    {"after": CUT},
    {"before": CUT},
    {"updated_since": CUT},
    {"filter[updated_at_greater_than]": CUT},
    {"filter[created_at_greater_than]": CUT},
    {"date_from": CUT},
]


def meta_total(ep, params):
    try:
        r = requests.get(BASE + "/" + ep, headers=HEADERS,
                         params={**params, "page": 1, "per_page": 1}, timeout=60)
    except Exception as e:
        return None, "ERR " + str(e)[:80]
    if r.status_code != 200:
        return None, str(r.status_code) + " " + (r.text or "")[:120]
    m = r.json().get("meta") or {}
    total = m.get("total_count", m.get("total"))
    return total, "ok"


for ep in ("treatment_plan_items", "treatment_plans"):
    print("\n=== " + ep + " ===")
    for params in CANDIDATES:
        total, note = meta_total(ep, params)
        label = params if params else "(baseline no filter)"
        print("  total={!s:<9} {!s:<12} {}".format(total, note, label))
