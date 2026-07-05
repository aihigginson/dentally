"""
dentally_appointments.py  --  Focused diagnostic for the appointments endpoint (0 rows).

Tries several filter forms (Dentally's appointments index requires a filter) using real
patient/practitioner ids from the earlier discovery dump, and prints Dentally's RAW
response for each so we can see whether it's a filter-syntax issue or a token-scope one.

Usage:  python API/dentally_appointments.py   (run dentally_explore.py first)
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


def sample_id(name):
    try:
        rows = json.load(open(os.path.join(DATA, name + ".json")))
        return rows[0]["id"] if rows else None
    except Exception:
        return None


def show(label, params):
    r = requests.get(BASE + "/appointments", headers=HEADERS, params={**params, "per_page": 3}, timeout=30)
    print(f"\n--- {label}  (HTTP {r.status_code}) ---")
    try:
        j = r.json()
        meta = j.get("meta", {})
        rows = next((v for k, v in j.items() if k != "meta"), [])
        n = len(rows) if isinstance(rows, list) else "?"
        print(f"  meta={json.dumps(meta)[:200]}  rows_on_page={n}")
        if isinstance(rows, list) and rows:
            print("  first appointment fields: " + str(sorted(rows[0].keys())))
    except Exception:
        print("  body: " + (r.text or "")[:400])


pid  = sample_id("patients")
prid = sample_id("practitioners")
print(f"Base: {BASE}   using patient_id={pid}  practitioner_id={prid}")

show("no filter",                    {})
show("filter[start_time]/finish",    {"filter[start_time]": "2022-01-01T00:00:00Z", "filter[finish_time]": "2027-01-01T00:00:00Z"})
show("start_time/finish_time",       {"start_time": "2022-01-01T00:00:00Z", "finish_time": "2027-01-01T00:00:00Z"})
show("before/after",                 {"after": "2022-01-01T00:00:00Z", "before": "2027-01-01T00:00:00Z"})
if pid:  show("patient_id",          {"patient_id": pid})
if pid:  show("filter[patient_id]",  {"filter[patient_id]": pid})
if prid: show("practitioner_id",     {"practitioner_id": prid})
