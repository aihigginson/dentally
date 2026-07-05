"""
dentally_explore.py  --  Real Dentally API discovery run (read-only).

Uses your token to pull a small sample from key endpoints and print what the REAL API
returns -- so we can reconcile field names/shapes against the mock (which drives the
current warehouse), and specifically HUNT for where lab fees live (custom fields on a
treatment-plan-item). Saves raw JSON to API/dentally_data/ (gitignored) for inspection.

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

# Curated: reference first (identity/structure), then a 1-page sample of the
# transactional entities that matter for practitioner production + the lab hunt.
ENDPOINTS = [
    "practices", "sites", "users", "practitioners", "treatments",
    "patients", "appointments", "invoices", "invoice_items",
    "treatment_plans", "treatment_plan_items", "payments",
]


def save(name, obj):
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, name + ".json"), "w") as f:
        json.dump(obj, f, indent=2)


def get(path, params=None):
    r = requests.get(BASE + path, headers=HEADERS, params=params or {}, timeout=30)
    return r


def main():
    print(f"Base: {BASE}\n")
    for ep in ENDPOINTS:
        r = get("/" + ep, {"page": 1, "per_page": 5})
        if r.status_code != 200:
            body = (r.text or "")[:160].replace("\n", " ")
            print(f"{ep:22} HTTP {r.status_code}  {body}")
            continue
        data = r.json()
        # Dentally wraps the list under the entity key, plus a 'meta' block.
        keys = [k for k in data if k != "meta"]
        entity = keys[0] if keys else None
        rows = data.get(entity, []) if entity else []
        meta = data.get("meta", {})
        total = meta.get("total_count", meta.get("total", "?"))
        fields = sorted(rows[0].keys()) if rows else []
        rl = r.headers.get("X-RateLimit-Remaining") or r.headers.get("RateLimit-Remaining")
        print(f"{ep:22} OK  total={total:<7} page1={len(rows)}  "
              f"fields={fields}" + (f"  [rate-remaining {rl}]" if rl else ""))
        save(ep, rows)

    # Deep-dump one treatment-plan-item in full: this is where lab fees / custom fields
    # would hide (they aren't in the standard schema).
    r = get("/treatment_plan_items", {"page": 1, "per_page": 5})
    if r.status_code == 200:
        rows = next((v for k, v in r.json().items() if k != "meta"), [])
        if rows:
            print("\n=== FULL first treatment_plan_item (hunt for lab fee / custom fields) ===")
            print(json.dumps(rows[0], indent=2)[:2500])

    print(f"\nRaw samples saved to {DATA}")


if __name__ == "__main__":
    main()
