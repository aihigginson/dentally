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
only_entities = []       # RESUME: e.g. ["treatment_plans","fees"] to pull ONLY these (skip the
                         # ones already landed after a partial run); [] = every entity
per_page      = 100      # 100 is Dentally's MAX per page -- asking for more silently falls back
                         # to 25 (=> more calls), so leave at 100. (Confirmed against the API.)
history_floor = "2024-04-01T00:00:00Z"  # updated_after floor applied ONLY to the huge historical
                         # tables (treatment_plans / treatment_plan_items); "" = full history.
                         # Those two span many years (items ~1.32M full vs ~107k from 2024-04) so
                         # flooring keeps the pull inside a single rate window (no sleep-to-reset,
                         # which is the fragile path). 'updated_after' is the confirmed filter and
                         # matches on UPDATED date, not created.
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
    # Confirmed limit: x-ratelimit-limit=3600/hour, x-ratelimit-reset = unix epoch on the hour
    # (top of each clock hour). Draining to 0 gets a 403 temp-block, so we stop at RATE_FLOOR.
    (r'''RATE_FLOOR = 5      # when x-ratelimit-remaining hits this, sleep to the window reset
MAX_WAIT   = 3700   # clamp any single rate sleep to ~1h (reset is an epoch on the hour)
MAX_429    = 200    # 429 retries before giving up (each waits to reset -> effectively never skips)
# Appointments + rota require an after/before window (plain params, NOT filter[...]).
WINDOW = {"after": "2022-01-01T00:00:00Z", "before": "2027-01-01T00:00:00Z"}
# These two big historical tables get an updated_after floor (history_floor param) so they fit in
# one rate window; every other entity keeps full history. Confirmed filter param: updated_after.
HISTORY_FLOOR_ENTITIES = {"treatment_plans", "treatment_plan_items"}
''', False),

    # 4 -- API helpers (rate-aware: sleep to the window reset, never skip on 429) ----
    (r'''def _wait_seconds(resp, default):
    # Seconds to wait, from Retry-After or RateLimit-Reset. Handles delta-seconds OR a unix
    # epoch, and clamps to [1, MAX_WAIT] so a malformed header can't sleep for ever.
    for h in ("Retry-After", "RateLimit-Reset", "X-RateLimit-Reset", "RateLimit-Reset-After"):
        v = resp.headers.get(h)
        if v and str(v).isdigit():
            n = int(v)
            if n > 100000:                       # looks like a unix epoch -> convert to delta
                n = n - int(time.time())
            return max(1, min(n + 1, MAX_WAIT))
    return default

def req(base, headers, path, params):
    # Survive Dentally's ~3600/hr budget: on 429 wait to the reset and retry (won't skip data);
    # when the remaining budget hits RATE_FLOOR, sleep to the window reset (not a fixed dribble).
    attempt = 0
    while True:
        attempt += 1
        r = requests.get(base + path, headers=headers, params=params, timeout=90)
        if r.status_code == 429:
            wait = _wait_seconds(r, 30)
            print("      429 rate-limited (try " + str(attempt) + "); sleeping " + str(wait) + "s")
            time.sleep(wait)
            if attempt >= MAX_429:
                raise RuntimeError("Rate-limited " + str(MAX_429) + "x on " + path)
            continue
        r.raise_for_status()
        rem = r.headers.get("RateLimit-Remaining") or r.headers.get("X-RateLimit-Remaining")
        if rem is not None and str(rem).isdigit() and int(rem) <= RATE_FLOOR:
            wait = _wait_seconds(r, 60)
            print("      budget low (" + str(rem) + "); sleeping " + str(wait) + "s to window reset")
            time.sleep(wait)
        return r

def fetch_all(base, headers, ep, params=None, max_pages=None):
    # Page until a short/empty page. size = the server's ACTUAL page-1 count, so a per_page the
    # API silently caps below what we asked can't trigger an early stop. Logs every 10 pages.
    out, page, size = [], 1, None
    while True:
        r = req(base, headers, "/" + ep, dict(params or {}, page=page, per_page=per_page))
        rows = next((v for k, v in r.json().items() if k != "meta"), [])
        if isinstance(rows, dict):
            rows = [rows]
        n = len(rows)
        if size is None:
            size = n
        out.extend(rows)
        if page % 10 == 0:
            print("      " + ep + " page " + str(page) + " (" + str(len(out)) + " rows so far)")
        if n == 0 or (size and n < size) or (max_pages and page >= max_pages):
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
    # The practitioner has NO name of its own -- name/email/role live in the nested `user`
    # object (real Dentally). Flatten with the SAME `user_`-prefixed names Bronze expects
    # (the mock delivered them that way). Keep contract_targets (Bronze reads it as a string);
    # keep top-level site_id; drop only the nested user/site objects + specialisms.
    u = r.get("user") or {}
    out = _drop(r, {"user", "site", "specialisms"})
    out.update({"user_id": u.get("id"),
                "user_first_name": u.get("first_name"),
                "user_middle_name": u.get("middle_name"),
                "user_last_name": u.get("last_name"),
                "user_title": u.get("title"),
                "user_role": u.get("role"),
                "user_email": u.get("email"),
                "user_mobile_phone": u.get("mobile_phone"),
                "user_image_url": u.get("image_url"),
                "user_created_at": u.get("created_at"),
                "user_updated_at": u.get("updated_at"),
                "user_last_login": u.get("last_login"),
                "user_permission_level": u.get("permission_level")})
    return out, {}

def t_patient(r):
    return _drop(r, PII_DROP), {}

def t_payment(r):
    exps = [dict(e, payment_id=r.get("id")) for e in (r.get("explanations") or [])]
    return _drop(r, {"explanations"}), {"payment_explanations": exps}

def t_rota(r):
    # Bronze.Practitioner_Diary_Breaks keys the parent as practitioner_diary_id (not rota_id).
    brks = [dict(b, practitioner_diary_id=r.get("id"), practitioner_id=r.get("practitioner_id"),
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

# opening_hours is a nested {DayName: {open, close}} object. Flatten to the flat per-day
# columns Bronze reads: practice -> oh_<abbr>_open/close (Mon-Sun); sites -> <day>_open/close
# (Mon-Fri). Days the practice/site isn't open (e.g. weekends) are simply absent -> NULL.
_HOURS_DOW = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
_HOURS_ABBR = {"Monday": "mon", "Tuesday": "tues", "Wednesday": "wed", "Thursday": "thur",
               "Friday": "fri", "Saturday": "sat", "Sunday": "sun"}

def _flatten_hours(r, prefix, days):
    oh = r.get("opening_hours") or {}
    out = _drop(r, {"opening_hours"})
    for day in days:
        slot = oh.get(day) or {}
        key = _HOURS_ABBR[day] if prefix == "oh_" else day.lower()
        out[prefix + key + "_open"] = slot.get("open")
        out[prefix + key + "_close"] = slot.get("close")
    return out

def t_practice(r):
    return _flatten_hours(r, "oh_", _HOURS_DOW), {}         # oh_mon_open .. oh_sun_close

def t_site(r):
    return _flatten_hours(r, "", _HOURS_DOW[:5]), {}        # monday_open .. friday_close

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
    ("practice",                         "practice",              "one", t_practice),
    ("sites",                            "sites",                 "ref", t_site),
    ("users",                            "users",                 "ref", passthrough),
    ("practitioners",                    "practitioners",         "ref", t_practitioner),
    ("payment_plans",                    "payment_plans",         "ref", passthrough),
    ("treatments",                       "treatments",            "ref", passthrough),
    ("treatment_categories",             "treatment_categories",  "ref", passthrough),
    ("acquisition_sources",              "acquisition_sources",   "ref", passthrough),
    ("appointment_cancellation_reasons", "cancellation_reasons",  "ref", passthrough),
    ("sundries",                         "sundries",              "ref", passthrough),
    ("contracts",                        "contracts",             "ref", passthrough),
    ("waiting_lists",                    "waiting_lists",         "ref", passthrough),
    ("appointments",                     "appointments",          "win", t_appointment),
    ("rota_practitioner_diaries",        "practitioner_diary_entries", "win", t_rota),
    ("patients",                         "patients",              "txn", t_patient),
    ("accounts",                         "accounts",              "txn", passthrough),
    ("invoices",                         "invoices",              "txn", passthrough),
    ("invoice_items",                    "invoice_items",         "txn", passthrough),
    ("payments",                         "payments",              "txn", t_payment),
    ("treatment_plans",                  "treatment_plans",       "txn", passthrough),
    ("treatment_plan_items",             "treatment_plan_items",  "txn", t_tp_item),
    ("recalls",                          "recalls",               "txn", passthrough),
    ("nhs_claims",                       "nhs_claims",            "txn", passthrough),
    ("treatment_appointments",           "treatment_appointments","txn", passthrough),
    ("patient_referrals",                "patient_referrals",     "txn", passthrough),
]
# NOTE: stage_payment_allocations is the remaining gap -- real Dentally nests allocations
# inside payment.explanations[] (landed as stage_payment_explanations); confirm whether a
# standalone /payment_allocations endpoint also exists or the Bronze load should read the
# explanations. Each pull below is wrapped tolerant, so an endpoint that 404s for a given
# practice (e.g. an unused feature) logs SKIP and the rest still land.
''', False),

    # 8 -- main: pull -> transform -> land ------------------------------------
    (r'''for tid, cfg in TOKENS.items():
    if only_tenant and str(tid) != str(only_tenant):
        continue
    base    = cfg.get("base_url", "https://api.dentally.co/v1").rstrip("/")
    headers = {"Authorization": "Bearer " + cfg["token"], "Accept": "application/json"}
    print("\nTenant", tid, "(" + cfg.get("name", "") + ") @", base)

    # only_entities RESUMES + sets ORDER: if given, run exactly those in the order listed
    # (else every entity in registry order). Match by endpoint or stage-table name.
    if only_entities:
        by_key = {}
        for e in REGISTRY:
            by_key[e[0]] = e; by_key[e[1]] = e
        run_list = [by_key[k] for k in only_entities if k in by_key]
    else:
        run_list = list(REGISTRY)

    all_patient_ids = []   # captured from the patients pull; used to gap-fill patient_stats
    for ep, stage_name, kind, fn in run_list:
        try:  # one bad/absent endpoint must not abort the whole practice's ingest
            if kind == "one":
                raw_rows = [fetch_one(base, headers, ep)]
            elif kind == "win":
                raw_rows = fetch_all(base, headers, ep, WINDOW, max_pages=cap)
            elif kind == "txn":
                p = dict(inc)
                if history_floor and ep in HISTORY_FLOOR_ENTITIES:
                    p["updated_after"] = history_floor   # floor the huge historical tables
                raw_rows = fetch_all(base, headers, ep, p, max_pages=cap)
            else:  # ref -- always full
                raw_rows = fetch_all(base, headers, ep)
            if ep == "patients":
                all_patient_ids = [r.get("id") for r in raw_rows
                                   if isinstance(r, dict) and r.get("id") is not None]
            # Dentally's bulk pagination is unstable and serves some rows TWICE (patient_stats
            # worst; also treatment_plan_items, recalls). Dedup within-entity by id -- keep first;
            # harmless when there are none. (The equal number of SKIPPED rows can't be recovered
            # here; run Check_Stage_Duplicates.sql after a pull to confirm clean.)
            if raw_rows and isinstance(raw_rows[0], dict) and "id" in raw_rows[0]:
                _seen, _dd = set(), []
                for r in raw_rows:
                    rid = r.get("id")
                    if rid is None or rid not in _seen:
                        _seen.add(rid); _dd.append(r)
                if len(_dd) != len(raw_rows):
                    print("      " + ep + ": deduped " + str(len(raw_rows) - len(_dd)) + " pagination twin(s)")
                raw_rows = _dd
            main, children = [], {}
            for r in raw_rows:
                m, ch = fn(r)
                main.append(m)
                for cname, crows in ch.items():
                    children.setdefault(cname, []).extend(crows)
            write_stage(main, stage_name, tid)
            for cname, crows in children.items():
                write_stage(crows, cname, tid)
        except Exception as e:
            print("  SKIP " + ep + ": " + str(e)[:200])

    # fees: one call per treatment (fees?treatment_id=) -- 5 price/duration tiers each.
    # In sample mode cap to a few treatments (the sweep is otherwise full even when sampling).
    if (not only_entities) or ("fees" in only_entities):
        try:
            treatments = fetch_all(base, headers, "treatments")
            if cap:
                treatments = treatments[:10]
            fees = []
            for t in treatments:
                fees.extend(fetch_all(base, headers, "fees", {"treatment_id": t["id"]}))
            write_stage(fees, "fees", tid)
        except Exception as e:
            print("  SKIP fees: " + str(e)[:200])

    # patient_stats: Dentally's BULK /patient_stats pagination is broken -- its pages are not
    # stably ordered, so it serves ~6% of records twice and SKIPS as many (confirmed: 27,747
    # rows / 26,116 distinct / 1,631 dups == 1,631 missing). So: pull the bulk set, dedup by
    # patient_id, then GAP-FILL the skipped patients via the reliable per-patient endpoint
    # GET /patients/{id}/stats (returns exactly one correct record; 404 = genuinely no stats).
    if (not only_entities) or ("patient_stats" in only_entities):
        try:
            if not all_patient_ids:   # resume run without patients -> fetch the id list first
                all_patient_ids = [r.get("id") for r in fetch_all(base, headers, "patients", inc)
                                   if isinstance(r, dict) and r.get("id") is not None]
            seen = {}                 # patient_id -> stats row (first wins; dups are identical)
            for r in fetch_all(base, headers, "patient_stats", inc, max_pages=cap):
                pid = r.get("patient_id")
                if pid is not None and pid not in seen:
                    seen[pid] = r
            missing = [pid for pid in all_patient_ids if pid not in seen]
            if cap:                   # smoke test: don't gap-fill thousands
                missing = missing[:10]
            print("  patient_stats: bulk " + str(len(seen)) + " deduped; gap-filling "
                  + str(len(missing)) + " skipped patients via /patients/{id}/stats")
            for pid in missing:
                try:
                    rr = req(base, headers, "/patients/" + str(pid) + "/stats", {})
                    obj = next((v for k, v in rr.json().items() if k != "meta"), None)
                    if isinstance(obj, dict):
                        obj.setdefault("patient_id", pid)
                        seen[pid] = obj
                except Exception:
                    pass              # 404 -> patient genuinely has no stats
            write_stage(list(seen.values()), "patient_stats", tid)
        except Exception as e:
            print("  SKIP patient_stats: " + str(e)[:200])

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
