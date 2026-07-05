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
    "practice", "sites", "users", "practitioners", "treatments",
    "patients", "appointments", "invoices", "invoice_items",
    "treatment_plans", "treatment_plan_items", "payments",
]

HUNT_PAGES = 60   # pages (x100) of treatment_plan_items to scan for NON-NULL custom_fields
# Candidate endpoints that would NAME the custom-field GUIDs (probed; 404 = not that name).
DEF_PROBES = ["custom_field_definitions", "custom_fields", "practice/custom_fields"]


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
        # Dentally wraps the list under the entity key, plus a 'meta' block. Singular
        # endpoints (e.g. /practice) return a single object rather than a list.
        keys = [k for k in data if k != "meta"]
        entity = keys[0] if keys else None
        _val = data.get(entity) if entity else None
        rows = [_val] if isinstance(_val, dict) else (_val if isinstance(_val, list) else [])
        meta = data.get("meta", {})
        total = meta.get("total_count", meta.get("total", "?"))
        fields = sorted(rows[0].keys()) if rows else []
        rl = r.headers.get("X-RateLimit-Remaining") or r.headers.get("RateLimit-Remaining")
        print(f"{ep:22} OK  total={total:<7} page1={len(rows)}  "
              f"fields={fields}" + (f"  [rate-remaining {rl}]" if rl else ""))
        save(ep, rows)

    # ── Name the custom-field GUIDs, if an endpoint exposes the definitions ──────
    print("\n=== Custom-field definition probes ===")
    for p in DEF_PROBES:
        r = get("/" + p, {"per_page": 50})
        if r.status_code == 200:
            d = r.json()
            rows = next((v for k, v in d.items() if k != "meta"), d)
            print(f"  {p}: OK -> {json.dumps(rows)[:600]}")
        else:
            print(f"  {p}: HTTP {r.status_code}")

    # ── Lab-fee hunt: find treatment_plan_items with a NON-NULL custom_field value ─
    print(f"\n=== Lab hunt: scanning up to {HUNT_PAGES} pages for NON-NULL custom values ===")
    scanned = with_value = with_lab_note = 0
    examples = []
    for page in range(1, HUNT_PAGES + 1):
        r = get("/treatment_plan_items", {"page": page, "per_page": 100})
        if r.status_code != 200:
            print(f"  page {page}: HTTP {r.status_code}"); break
        rows = next((v for k, v in r.json().items() if k != "meta"), [])
        if not rows:
            break
        for it in rows:
            scanned += 1
            non_null = [f for f in (it.get("custom_fields") or []) if f.get("value") not in (None, "")]
            if non_null:
                with_value += 1
                if len(examples) < 6:
                    examples.append({"id": it.get("id"), "price": it.get("price"),
                                     "nom": it.get("nomenclature"), "custom_fields": non_null})
            if "lab" in ((it.get("notes") or "") + " " + (it.get("nomenclature") or "")).lower():
                with_lab_note += 1
    print(f"  scanned {scanned}: {with_value} with a NON-NULL custom value, {with_lab_note} 'lab' notes")
    if examples:
        print("  --- items with NON-NULL custom values (does any look like a lab fee?) ---")
        print(json.dumps(examples, indent=2)[:2500])
    else:
        print("  -> NO treatment_plan_item in the scan has a populated custom-field value.")

    print(f"\nRaw samples saved to {DATA}")


if __name__ == "__main__":
    main()
