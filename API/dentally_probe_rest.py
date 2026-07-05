"""
dentally_probe_rest.py  --  Probe the remaining warehouse entities (read-only).

The core 15 are mapped (DENTALLY_RECONCILIATION.md); the warehouse ingests ~12 more.
Their real endpoint names / filter needs are uncertain, so this tries candidate names
per entity, and if one 200s-but-empty it retries with a date window (some indexes, like
appointments, need after/before). Prints each entity's real fields; saves samples.

Usage:  python API/dentally_probe_rest.py
"""
import importlib.util
import json
import os

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "dentally_data")

_s = importlib.util.spec_from_file_location("dentally_creds_local", os.path.join(HERE, "dentally_creds.local.py"))
creds = importlib.util.module_from_spec(_s); _s.loader.exec_module(creds)
BASE    = creds.DENTALLY_BASE.rstrip("/")
HEADERS = {"Authorization": "Bearer " + creds.DENTALLY_TOKEN, "Accept": "application/json"}
WINDOW  = {"after": "2022-01-01T00:00:00Z", "before": "2027-01-01T00:00:00Z"}

# Each group = candidate endpoint names to try in order (first that works wins).
CANDIDATES = [
    ["rooms"],
    ["sundries"],
    ["fees"],
    ["recalls"],
    ["nhs_claims", "nhs_claim_forms"],
    ["practitioner_diary_entries", "practitioner_diaries", "diaries"],
    ["practitioner_diary_breaks", "diary_breaks", "practitioner_breaks"],
    ["acquisition_sources"],
    ["appointment_cancellation_reasons", "cancellation_reasons"],
    ["patient_referrals", "referrals"],
    ["patient_stats"],
    ["treatment_appointments"],
]


def probe(name, params=None):
    return requests.get(BASE + "/" + name, headers=HEADERS,
                        params={**(params or {}), "page": 1, "per_page": 3}, timeout=30)


def rows_of(r):
    j = r.json()
    rows = next((v for k, v in j.items() if k != "meta"), [])
    if isinstance(rows, dict):
        rows = [rows]
    total = (j.get("meta") or {}).get("total_count", (j.get("meta") or {}).get("total"))
    return rows, total


def save(name, rows):
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, name + ".json"), "w") as f:
        json.dump(rows, f, indent=2)


print(f"Base: {BASE}\n")
for group in CANDIDATES:
    done = False
    for name in group:
        r = probe(name)
        if r.status_code == 404:
            continue
        if r.status_code != 200:
            print(f"{name:30} HTTP {r.status_code}  {(r.text or '')[:100]}")
            done = True; break
        rows, total = rows_of(r)
        if not rows and (total in (0, "0", None)):
            r2 = probe(name, WINDOW)                      # maybe needs a date window
            rows, total = rows_of(r2)
            tag = " (needs after/before)" if rows else " -> 0 (empty or other filter)"
        else:
            tag = ""
        fields = sorted(rows[0].keys()) if rows else []
        print(f"{name:30} OK  total={str(total):<8}{tag}  fields={fields}")
        if rows:
            save(name, rows)
        done = True; break
    if not done:
        print(f"{'/'.join(group):30} -> all candidates 404 (not that name)")
