"""
build_Ingest_Dentally.py  --  Generator for Ingest_Dentally.ipynb (Fabric notebook).

Edit THIS file, then run `python build_Ingest_Dentally.py` to regenerate the notebook.
We never hand-edit the .ipynb JSON: source must be a list-of-lines and manual edits
have corrupted these notebooks before. Cell sources are plain Python strings here and
this script emits valid nbformat-4 JSON (source split to lines).

This is the REAL Dentally Stage_Ingest (task B). It reads the practice token(s) from
Key Vault (dentally-tokens-<env>), pulls every warehouse entity from api.dentally.co,
applies the DENTALLY_RECONCILIATION.md transforms (flatten nested .user/.site +
payment.explanations[] + rota.breaks[]; DROP patient PII/free-text per DPIA V011/V012;
handle nulls), and lands the SAME stage_* table names the mock Stage_Ingest produced so
the existing Bronze/Silver/Gold build runs unchanged. Transforms mirror -- and were
validated against real sample data by -- API/dentally_transform.py.
"""
import json
import os

# Each cell: (raw source string, is_parameters_cell). Keep cell code free of triple
# quotes. Runs in Fabric: `spark` and `notebookutils` are provided by the runtime.
CELLS = [
    # 0 -- parameters (Fabric overrides at pipeline runtime) -------------------
    (r'''# Parameters -- Fabric overrides these at pipeline runtime.
keyvault_url  = "https://kv-analytically.vault.azure.net/"
dentally_env  = "dev"    # which env's tokens: dentally-tokens-<env> (dev|prod). PROD passes "prod".
only_tenant   = ""       # optional Tenant_ID to restrict to; blank = every mapped practice
full_refresh  = True     # True = full pull; False = incremental via updated_after
updated_after = ""       # ISO8601 incremental start; blank + not full = last 24h
sample_pages  = 0        # >0 caps pages/entity for a quick smoke test; 0 = no cap
''', True),

    # 1 -- imports -------------------------------------------------------------
    (r'''import json
import time
from datetime import datetime, timezone, timedelta

import requests
from pyspark.sql.types import StringType, StructType, StructField
import notebookutils
''', False),

    # 2 -- Key Vault + token load ---------------------------------------------
    (r'''# --- Key Vault ---------------------------------------------------------------
# dentally-tokens-<env> : JSON {"<Tenant_ID>": {"token": "...", "base_url": "...",
#                         "name": "..."}} -- one entry per practice. The run identity
#                         (pipeline/workspace) needs secrets 'get' on the vault.
def kv_get(name):
    return notebookutils.credentials.getSecret(keyvault_url, name)

raw = (kv_get("dentally-tokens-" + dentally_env) or "").lstrip("﻿").strip()
TOKENS = json.loads(raw) if raw else {}
if not TOKENS:
    raise SystemExit("dentally-tokens-" + dentally_env + " is empty/missing -- load a token first.")

cap = sample_pages or None
if not updated_after and not full_refresh:
    updated_after = (datetime.now(timezone.utc) - timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M:%S")
load_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
inc = {} if full_refresh else {"updated_after": updated_after}
print("Env", dentally_env, "| mode", "FULL" if full_refresh else ("incremental from " + updated_after),
      "| tenants", list(TOKENS.keys()))
''', False),

    # 3 -- config --------------------------------------------------------------
    (r'''PER_PAGE = 100
MAX_429  = 6
# Appointments + rota require an after/before window (plain params, NOT filter[...]).
WINDOW = {"after": "2022-01-01T00:00:00Z", "before": "2027-01-01T00:00:00Z"}
''', False),

    # 4 -- API helpers (from API/dentally_extract.py) --------------------------
    (r'''def req(base, headers, path, params):
    # GET with 429 backoff + a pause when the rate budget (RateLimit-Remaining ~3600) runs low.
    for _ in range(MAX_429):
        r = requests.get(base + path, headers=headers, params=params, timeout=60)
        if r.status_code == 429:
            wait = int(r.headers.get("Retry-After", 30)) + 1
            print("      429 rate-limited; sleeping", wait, "s")
            time.sleep(wait)
            continue
        r.raise_for_status()
        rem = r.headers.get("RateLimit-Remaining") or r.headers.get("X-RateLimit-Remaining")
        if rem and rem.isdigit() and int(rem) < 50:
            print("      rate budget low (" + rem + "); pausing 20s")
            time.sleep(20)
        return r
    raise RuntimeError("Rate-limited repeatedly on " + path)

def fetch_all(base, headers, ep, params=None, max_pages=None):
    # Walk page/per_page pagination. Terminate on a SHORT page -- NOT meta.total_pages,
    # which some endpoints (patients/treatment_plan_items/payments) omit (defaults to 1).
    out, page = [], 1
    while True:
        r = req(base, headers, "/" + ep, dict(params or {}, page=page, per_page=PER_PAGE))
        rows = next((v for k, v in r.json().items() if k != "meta"), [])
        if isinstance(rows, dict):
            rows = [rows]
        out.extend(rows)
        if len(rows) < PER_PAGE or (max_pages and page >= max_pages):
            return out
        page += 1

def fetch_one(base, headers, ep):
    r = req(base, headers, "/" + ep, {})
    return next((v for k, v in r.json().items() if k != "meta"), {})
''', False),

    # 5 -- transforms (validated by API/dentally_transform.py) -----------------
    (r'''# Flatten/drop/fix from DENTALLY_RECONCILIATION.md. Each returns (main, {child_stage: [rows]}).
# tenant_id is NOT stamped here -- write_stage stamps every row (incl. children).

# Special-category / PII to NEVER land (DPIA V011/V012). Patients.
PII_DROP = {
    "date_of_birth", "gender", "ethnicity", "nhs_number", "ni_number", "pps_number",
    "medical_alert", "medical_alert_text", "special_needs", "occupation", "school_name",
    "emergency_contact_name", "emergency_contact_phone", "emergency_contact_phone_country",
    "emergency_contact_phone_normalized", "emergency_contact_relationship",
    "proof_of_identification", "suspicious_identity", "image_url", "metadata", "custom_fields",
}

def _drop(r, keys):
    return {k: v for k, v in r.items() if k not in keys}

def t_practitioner(r):
    u = r.get("user") or {}
    out = _drop(r, {"user", "site", "specialisms", "contract_targets"})
    out.update({"user_id": u.get("id"), "first_name": u.get("first_name"),
                "middle_name": u.get("middle_name"), "last_name": u.get("last_name"),
                "email": u.get("email"), "role": u.get("role"),
                "permission_level": u.get("permission_level")})
    return out, {}

def t_patient(r):
    return _drop(r, PII_DROP), {}

def t_payment(r):
    exps = [dict(e, payment_id=r.get("id")) for e in (r.get("explanations") or [])]
    return _drop(r, {"explanations"}), {"payment_explanations": exps}

def t_rota(r):
    brks = [dict(b, rota_id=r.get("id"), practitioner_id=r.get("practitioner_id"),
                 day=r.get("day")) for b in (r.get("breaks") or [])]
    return _drop(r, {"breaks"}), {"practitioner_diary_breaks": brks}

def t_tp_item(r):
    out = _drop(r, {"notes", "custom_fields"})
    for k in ("teeth", "surfaces"):
        if isinstance(out.get(k), list):
            out[k] = json.dumps(out[k])
    return out, {}

def t_appointment(r):
    return _drop(r, {"notes", "metadata"}), {}

def passthrough(r):
    return r, {}
''', False),

    # 6 -- write_stage (Spark Delta, per-tenant replaceWhere; mock table names) -
    (r'''def _to_str(v):
    if v is None:
        return None
    if isinstance(v, (dict, list)):
        return json.dumps(v)
    return str(v)

def write_stage(records, table_name, tenant_id):
    # Lands stage_<table_name>; all values strings (Bronze does the typing). Scoped to
    # this tenant so multiple practices coexist. Same shape/names as the mock Stage_Ingest.
    full = "stage_" + table_name
    if not records:
        print("  " + table_name + ": 0 rows")
        return
    for r in records:
        r["tenant_id"] = tenant_id
        r["DW_Stage_Loaded_At"] = load_timestamp
    keys = set()
    for r in records:
        keys.update(r.keys())
    schema = StructType([StructField(k, StringType(), True) for k in sorted(keys)])
    str_records = [{k: _to_str(r.get(k)) for k in keys} for r in records]
    df = spark.createDataFrame(str_records, schema=schema)
    if spark.catalog.tableExists(full):
        df.write.format("delta").mode("overwrite") \
            .option("replaceWhere", "tenant_id = '" + str(tenant_id) + "'") \
            .option("mergeSchema", "true").saveAsTable(full)
    else:
        df.write.format("delta").mode("overwrite") \
            .option("overwriteSchema", "true").saveAsTable(full)
    print("  " + table_name + ": " + str(len(records)) + " rows -> " + full)
''', False),

    # 7 -- entity registry -----------------------------------------------------
    (r'''# (endpoint, stage_table_name, kind, transform). stage names MATCH the mock so Bronze
# is unchanged. kind: one=single object; ref=full pull; win=needs after/before; txn=
# incremental-capable. Real->mock name remaps: appointment_cancellation_reasons->
# cancellation_reasons; rota_practitioner_diaries->practitioner_diary_entries (+ embedded
# breaks->practitioner_diary_breaks); payment.explanations[]->payment_explanations.
REGISTRY = [
    ("practice",                         "practice",              "one", passthrough),
    ("sites",                            "sites",                 "ref", passthrough),
    ("users",                            "users",                 "ref", passthrough),
    ("practitioners",                    "practitioners",         "ref", t_practitioner),
    ("payment_plans",                    "payment_plans",         "ref", passthrough),
    ("treatments",                       "treatments",            "ref", passthrough),
    ("treatment_categories",             "treatment_categories",  "ref", passthrough),
    ("acquisition_sources",              "acquisition_sources",   "ref", passthrough),
    ("appointment_cancellation_reasons", "cancellation_reasons",  "ref", passthrough),
    ("sundries",                         "sundries",              "ref", passthrough),
    ("contracts",                        "contracts",             "ref", passthrough),
    ("appointments",                     "appointments",          "win", t_appointment),
    ("rota_practitioner_diaries",        "practitioner_diary_entries", "win", t_rota),
    ("patients",                         "patients",              "txn", t_patient),
    ("invoices",                         "invoices",              "txn", passthrough),
    ("invoice_items",                    "invoice_items",         "txn", passthrough),
    ("payments",                         "payments",              "txn", t_payment),
    ("treatment_plans",                  "treatment_plans",       "txn", passthrough),
    ("treatment_plan_items",             "treatment_plan_items",  "txn", t_tp_item),
    ("recalls",                          "recalls",               "txn", passthrough),
    ("nhs_claims",                       "nhs_claims",            "txn", passthrough),
    ("patient_stats",                    "patient_stats",         "txn", passthrough),
    ("treatment_appointments",           "treatment_appointments","txn", passthrough),
    ("patient_referrals",                "patient_referrals",     "txn", passthrough),
]
# NOTE (reconciliation gaps to confirm on first real Bronze run): the mock also fed
# stage_accounts, stage_waiting_lists and stage_payment_allocations. Real Dentally has no
# confirmed /accounts or /waiting_lists endpoint, and nests allocations inside
# payment.explanations[]. If the corresponding Bronze loads error on a missing stage table,
# either (a) point them at the nested source, or (b) make those Bronze loads tolerant.
''', False),

    # 8 -- main: pull -> transform -> land ------------------------------------
    (r'''for tid, cfg in TOKENS.items():
    if only_tenant and str(tid) != str(only_tenant):
        continue
    base    = cfg.get("base_url", "https://api.dentally.co/v1").rstrip("/")
    headers = {"Authorization": "Bearer " + cfg["token"], "Accept": "application/json"}
    print("\nTenant", tid, "(" + cfg.get("name", "") + ") @", base)

    for ep, stage_name, kind, fn in REGISTRY:
        if kind == "one":
            raw_rows = [fetch_one(base, headers, ep)]
        elif kind == "win":
            raw_rows = fetch_all(base, headers, ep, WINDOW, max_pages=cap)
        elif kind == "txn":
            raw_rows = fetch_all(base, headers, ep, inc, max_pages=cap)
        else:  # ref -- always full
            raw_rows = fetch_all(base, headers, ep)
        main, children = [], {}
        for r in raw_rows:
            m, ch = fn(r)
            main.append(m)
            for cname, crows in ch.items():
                children.setdefault(cname, []).extend(crows)
        write_stage(main, stage_name, tid)
        for cname, crows in children.items():
            write_stage(crows, cname, tid)

    # fees: one call per treatment (fees?treatment_id=) -- 5 price/duration tiers each.
    treatments = fetch_all(base, headers, "treatments")
    fees = []
    for t in treatments:
        fees.extend(fetch_all(base, headers, "fees", {"treatment_id": t["id"]}))
    write_stage(fees, "fees", tid)

print("\nStage load complete. Bronze/Silver/Gold Dentally loads run next in the pipeline.")
''', False),
]


def build():
    cells = []
    for src, is_params in CELLS:
        cell = {
            "cell_type": "code",
            "execution_count": None,
            "metadata": {"tags": ["parameters"]} if is_params else {},
            "outputs": [],
            "source": src.splitlines(keepends=True),
        }
        cells.append(cell)
    nb = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 4,
    }
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Ingest_Dentally.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, indent=1)
        f.write("\n")
    return out


if __name__ == "__main__":
    path = build()
    print("Wrote", path)
