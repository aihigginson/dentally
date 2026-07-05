"""
dentally_explore.py  --  Real Dentally API "whole-cake" assessment (read-only).

Surveys every key endpoint, fixes the appointments endpoint (Dentally requires a time
window on it), confirms deep pagination works, and estimates the cost of a full initial
pull. Tells us whether the whole dataset is reachable before we build the real extractor.

Usage:  python API/dentally_explore.py
Reads DENTALLY_TOKEN / DENTALLY_BASE from API/dentally_creds.local.py.
"""
import importlib.util
import json
import os

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "dentally_data")

_p = os.path.join(HERE, "dentally_creds.local.py")
if not os.path.exists(_p):
    raise SystemExit("Missing API/dentally_creds.local.py (copy dentally_creds.example.py, paste your token).")
_s = importlib.util.spec_from_file_location("dentally_creds_local", _p)
creds = importlib.util.module_from_spec(_s)
_s.loader.exec_module(creds)

BASE    = creds.DENTALLY_BASE.rstrip("/")
HEADERS = {"Authorization": "Bearer " + creds.DENTALLY_TOKEN, "Accept": "application/json"}

ENDPOINTS = [
    "practice", "sites", "users", "practitioners", "treatments", "treatment_categories",
    "payment_plans", "contracts", "patients", "appointments", "invoices", "invoice_items",
    "treatment_plans", "treatment_plan_items", "payments",
]


def endpoint_params(ep, page=1, per_page=5):
    p = {"page": page, "per_page": per_page}
    if ep == "appointments":
        # Dentally requires a start/finish window on the appointments index.
        p["filter[start_time]"]  = "2022-01-01T00:00:00Z"
        p["filter[finish_time]"] = "2027-01-01T00:00:00Z"
    return p


def get(path, params=None):
    return requests.get(BASE + path, headers=HEADERS, params=params or {}, timeout=30)


def as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def save(name, obj):
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, name.replace("/", "_") + ".json"), "w") as f:
        json.dump(obj, f, indent=2)


def main():
    print(f"Base: {BASE}\n")
    totals = {}
    for ep in ENDPOINTS:
        r = get("/" + ep, endpoint_params(ep))
        if r.status_code != 200:
            print(f"{ep:22} HTTP {r.status_code}  {(r.text or '')[:120]}")
            totals[ep] = None
            continue
        data = r.json()
        keys = [k for k in data if k != "meta"]
        entity = keys[0] if keys else None
        _val = data.get(entity) if entity else None
        rows = [_val] if isinstance(_val, dict) else (_val if isinstance(_val, list) else [])
        meta = data.get("meta", {})
        total = meta.get("total_count", meta.get("total"))
        totals[ep] = as_int(total)
        fields = sorted(rows[0].keys()) if rows else []
        print(f"{ep:22} OK  total={str(total):<8} page1={len(rows)}  fields={len(fields)}")
        save(ep, rows)

    # ── Deep-pagination check: can we actually reach the far pages of the big tables? ──
    print("\n=== Deep-pagination check (per_page=100) ===")
    for ep in ("treatment_plan_items", "invoice_items", "appointments"):
        t = totals.get(ep)
        if not t:
            print(f"  {ep}: total {t} -> skip"); continue
        last = (t + 99) // 100
        probe = min(last, 50)   # a page well into the set
        r = get("/" + ep, endpoint_params(ep, page=probe, per_page=100))
        n = 0
        if r.status_code == 200:
            n = len(next((v for k, v in r.json().items() if k != "meta"), []))
        print(f"  {ep}: page {probe}/{last} -> HTTP {r.status_code}, {n} rows")

    # ── Whole-cake summary: total volume + full initial-pull cost ──
    print("\n=== Whole-cake summary (full initial pull @ per_page=100) ===")
    grand_rec = grand_calls = 0
    for ep in ENDPOINTS:
        t = totals.get(ep)
        if t is None:
            print(f"  {ep:22} (no count / not paged)"); continue
        calls = (t + 99) // 100
        grand_rec += t; grand_calls += calls
        print(f"  {ep:22} {t:>9,} records  ~{calls:>6,} calls")
    print(f"  {'TOTAL':22} {grand_rec:>9,} records  ~{grand_calls:>6,} calls")
    print("  A full initial pull is a rate-limited job (paginate + respect the limit +")
    print("  incremental via updated_after after the first load). Raw samples in dentally_data/.")


if __name__ == "__main__":
    main()
