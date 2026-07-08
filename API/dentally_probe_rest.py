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
    ["fees"],
    ["recalls", "patient_recalls"],
    ["available_hours", "availabilities", "working_hours", "practitioner_diary_entries", "diary"],
    ["practitioner_diary_breaks", "diary_breaks", "breaks"],
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


def sample_id(name, key="id"):
    try:
        rows = json.load(open(os.path.join(DATA, name + ".json")))
        return rows[0].get(key) if rows else None
    except Exception:
        return None


# Real ids from the earlier dump, for endpoints that require a filter.
site_id = sample_id("sites")
tid     = sample_id("treatments")
ppid    = sample_id("payment_plans")
pid     = sample_id("patients")
# Extra param-sets to try (in order) per entity when plain returns 0/400/500.
RETRY = {
    "fees":            [{"treatment_id": tid}, {"payment_plan_id": ppid}],
    "rooms":           [{"site_id": site_id}],
    "recalls":         [{"patient_id": pid}],
    "patient_recalls": [{"patient_id": pid}],
}

print(f"Base: {BASE}   (site={site_id}, treatment={tid}, payment_plan={ppid}, patient={pid})\n")
for group in CANDIDATES:
    done = False
    for name in group:
        try:
            r = probe(name)
        except Exception as e:
            print(f"{name:30} ERROR {e}"); done = True; break
        if r.status_code == 404:
            continue
        # Build the list of param-sets to attempt for this endpoint.
        attempts = [{}, WINDOW] + RETRY.get(name, [])
        got_rows, got_total, note = [], None, ""
        for i, params in enumerate(attempts):
            try:
                rr = r if i == 0 else probe(name, params)
            except Exception as e:
                continue
            if rr.status_code == 200:
                rows, total = rows_of(rr)
                if rows:
                    got_rows, got_total = rows, total
                    note = f" (params={params})" if params else ""
                    break
                got_total = total
            elif rr.status_code == 400:
                note = f" -> 400 {(rr.text or '')[:140]}"
        if got_rows:
            print(f"{name:30} OK  total={str(got_total):<8}{note}  fields={sorted(got_rows[0].keys())}")
            save(name, got_rows)
        else:
            print(f"{name:30} OK  total={str(got_total):<8} (no rows){note}")
        done = True; break
    if not done:
        print(f"{'/'.join(group):30} -> all candidates 404 (not that name)")
