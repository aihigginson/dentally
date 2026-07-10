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
full_refresh  = False    # DELTA by default (per-entity Bronze watermark, per bronze_watermark).
                         # Onboarding passes True for a one-off FULL pull. A delta run ignores
                         # both full_refresh(False) and history_floor for any WARM entity.
updated_after = ""       # ISO8601 incremental start; blank + not full = last 24h
sample_pages  = 0        # >0 caps pages/entity for a quick smoke test; 0 = no cap
run_uuid      = ""       # correlation id from Orchestrate_Build; blank -> fresh uuid. Progress -> Audit.Ingest_Log
only_entities = []       # RESUME: e.g. ["treatment_plans","fees"] to pull ONLY these (skip the
                         # ones already landed after a partial run); [] = every entity
per_page      = 100      # 100 is Dentally's MAX per page -- asking for more silently falls back
                         # to 25 (=> more calls), so leave at 100. (Confirmed against the API.)
history_floor = "2021-01-01T00:00:00Z"  # COLD-START-only floor for the updated_at-windowed historical
                         # tables treatment_plans / treatment_plan_items / treatment_appointments (NOT the
                         # diary `appointments`, which cold-windows by start_time between APPT_FLOOR/CEILING).
                         # Used ONLY when a tenant+entity has no Bronze rows yet;
                         # a WARM run uses the per-entity Bronze watermark instead (see bronze_watermark).
                         # Windowing keeps a cold full pull inside rate windows (deep-offset 413 otherwise).
                         # 'updated_after' is the confirmed filter and matches on UPDATED date, not created.
window_days   = 30       # ONBOARDING window size (days) for the floored historical tables. Dentally
                         # 413s on DEEP offset pagination (the scan-cost limit DRIFTS with load --
                         # seen ~50k one run, ~106k another), so we pull these in updated_at windows
                         # that each paginate from page 1 (shallow offsets). A window that still 413s
                         # is auto-halved. 30d is safe for a single practice; smaller = more windows
                         # but each cheaper. Deltas ignore this (few recent rows, no deep pages).
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
load_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
# No blanket 24h lookback (it silently dropped changes when a run was missed). Each txn entity pulls
# updated_after = its own Bronze high-watermark (bronze_watermark below); an explicit updated_after
# param is a manual override for ALL entities.
_mode = "FULL" if full_refresh else ("incremental from " + updated_after if updated_after else "incremental (per-entity Bronze watermark)")
print("Env", dentally_env, "| mode", _mode, "| tenants", list(TOKENS.keys()))
''', False),

    # 3 -- config --------------------------------------------------------------
    # Confirmed limit: x-ratelimit-limit=3600/hour, x-ratelimit-reset = unix epoch on the hour
    # (top of each clock hour). Draining to 0 gets a 403 temp-block, so we stop at RATE_FLOOR.
    (r'''RATE_FLOOR = 5      # when x-ratelimit-remaining hits this, sleep to the window reset
MAX_WAIT   = 3700   # clamp any single rate sleep to ~1h (reset is an epoch on the hour)
MAX_429    = 200    # 429 retries before giving up (each waits to reset -> effectively never skips)
MAX_5XX    = 4      # transient 5xx (recalls 500'd once, 200 on retry): back off + retry, don't skip the entity
# rota uses an `after` window (plain param, NOT filter[...]). NO `before` -- we want every future
# diary entry Dentally holds. (appointments moved to updated_after; the historical tables window on
# updated_at up to run time. No `before` date-cap on ANY entity -- future-dated rows are wanted.)
WINDOW = {"after": "2022-01-01T00:00:00Z"}
# appointments honours updated_after but NOT updated_before, so updated_at windowing can't tile it.
# Its COLD pull tiles by APPOINTMENT DATE (start_time via after/before -- both honoured, spread evenly
# across years so windows stay shallow) between these bounds; the ceiling captures future bookings.
APPT_FLOOR   = "2015-01-01T00:00:00Z"
APPT_CEILING = "2030-01-01T00:00:00Z"
# These big historical tables get an updated_after floor (history_floor) so a FULL/onboarding pull
# tiles into rate-window-sized chunks; on a DELTA run history_floor="" -> they use updated_after like
# everything else (few recent rows). treatment_appointments ALSO supports updated_after/updated_before
# (per the API docs), so it windows too -- the earlier "no date field / 413 full-pull" note was stale.
HISTORY_FLOOR_ENTITIES = {"treatment_plans", "treatment_plan_items", "treatment_appointments"}
PARTIAL_OK_413 = set()   # nothing full-pulls-with-413-tolerance now; windowed entities avoid deep offsets
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
        if 500 <= r.status_code < 600:
            # Transient server error (Dentally 500'd recalls page 1 once, 200 on retry). Back off
            # and retry a few times before letting it raise -> a blip won't skip the whole entity.
            if attempt <= MAX_5XX:
                back = min(5 * attempt, 30)
                print("      " + str(r.status_code) + " server error on " + path
                      + " (try " + str(attempt) + "); retrying in " + str(back) + "s")
                time.sleep(back)
                continue
            # exhausted retries -> fall through and raise below
        r.raise_for_status()
        rem = r.headers.get("RateLimit-Remaining") or r.headers.get("X-RateLimit-Remaining")
        if rem is not None and str(rem).isdigit() and int(rem) <= RATE_FLOOR:
            wait = _wait_seconds(r, 60)
            print("      budget low (" + str(rem) + "); sleeping " + str(wait) + "s to window reset")
            time.sleep(wait)
        return r

def fetch_all(base, headers, ep, params=None, max_pages=None, partial_ok_on_413=False):
    # Page until a short/empty page. size = the server's ACTUAL page-1 count, so a per_page the
    # API silently caps below what we asked can't trigger an early stop. Logs every 10 pages.
    # partial_ok_on_413: for entities that can't be windowed (treatment_appointments) -- on the
    # deep-offset 413, LAND the newest-first rows pulled so far instead of raising (which would
    # skip the whole entity and lose them, as happened on the first onboard).
    out, page, size = [], 1, None
    while True:
        try:
            r = req(base, headers, "/" + ep, dict(params or {}, page=page, per_page=per_page))
        except requests.HTTPError as e:
            if partial_ok_on_413 and getattr(e.response, "status_code", None) == 413:
                print("      !! " + ep + " deep-offset 413 at page " + str(page) + " -- landing the "
                      + str(len(out)) + " newest rows pulled so far; older links beyond the wall "
                      + "NOT pulled (per-patient backfill needed for full history).")
                return out
            raise
        rows = next((v for k, v in r.json().items() if k != "meta"), [])
        if isinstance(rows, dict):
            rows = [rows]
        n = len(rows)
        if size is None:
            size = n
        out.extend(rows)
        if page % 10 == 0:
            print("      " + ep + " page " + str(page) + " (" + str(len(out)) + " rows so far)")
            log_ingest(ep, "PAGE", rows=len(out), detail="page " + str(page))
        if n == 0 or (size and n < size) or (max_pages and page >= max_pages):
            return out
        page += 1

def fetch_one(base, headers, ep):
    r = req(base, headers, "/" + ep, {})
    return next((v for k, v in r.json().items() if k != "meta"), {})

# --- windowed fetch (onboarding of huge historical tables) -------------------
# Dentally 413s ("Content Too Large") on DEEP offset pagination, and the threshold is a server
# scan-COST budget that DRIFTS with load (a full pull reached offset ~106k one day, ~50k another --
# it "worked once then failed"). It is NOT a fixed wall and NOT response-size (per_page 25 at the
# same deep page is really just a smaller offset). Fix: tile the history into updated_at windows so
# every window paginates from page 1 and offsets stay shallow/cheap. A window that STILL 413s (a
# migration/bulk-update can re-timestamp thousands of old rows into one window) is retried once for
# a transient spike, then HALVED and recursed. `updated_before` is confirmed honored.
def _win_parse(s):
    s = str(s).strip().replace("Z", "").replace("z", "")
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return datetime.strptime(s[:10], "%Y-%m-%d")

def _win_fmt(d):
    return d.strftime("%Y-%m-%dT%H:%M:%S") + "Z"

def _is_413(e):
    return isinstance(e, requests.HTTPError) and getattr(e.response, "status_code", None) == 413

def _fetch_window(base, headers, ep, lo, hi, min_span, cap, unresolved, extra=None, after_key="updated_after", before_key="updated_before"):
    params = {after_key: _win_fmt(lo), before_key: _win_fmt(hi)}
    if extra:
        params.update(extra)
    for attempt in (1, 2):                       # 2nd try absorbs a transient/load-spike 413
        try:
            return fetch_all(base, headers, ep, params, max_pages=cap)
        except requests.HTTPError as e:
            if not _is_413(e):
                raise
            if attempt == 1:
                time.sleep(3)
    if (hi - lo) <= min_span:
        # More rows than the wall share a <=min_span timestamp span -- date windows can't split
        # identical/near-identical timestamps (a bulk-update/migration re-stamps thousands at once).
        # Do NOT drop it silently: record + shout so onboarding validation can't miss the gap.
        print("      !! 413 UNRESOLVED " + _win_fmt(lo) + ".." + _win_fmt(hi)
              + " -- too many rows updated in this span (migration cluster?); NOT landed")
        unresolved.append((_win_fmt(lo), _win_fmt(hi)))
        return []
    mid = lo + (hi - lo) / 2
    print("      413 on " + _win_fmt(lo) + ".." + _win_fmt(hi) + " -> halving")
    return (_fetch_window(base, headers, ep, lo, mid, min_span, cap, unresolved, extra, after_key, before_key)
            + _fetch_window(base, headers, ep, mid, hi, min_span, cap, unresolved, extra, after_key, before_key))

def fetch_windowed(base, headers, ep, floor, end, step_days=30, min_hours=1, cap=None, extra=None, after_key="updated_after", before_key="updated_before"):
    # Tile [floor,end] into step_days windows; halve any that 413 down to min_hours. Returns rows +
    # loudly flags any window that stays 413 at min_hours (bulk-update cluster -> raise history_floor
    # past it, or pull that span by id). Deltas don't use this (few recent rows).
    lo, end = _win_parse(floor), _win_parse(end)
    step, min_span = timedelta(days=step_days), timedelta(hours=min_hours)
    out, w, unresolved = [], 0, []
    while lo < end:
        hi = min(lo + step, end)
        rows = _fetch_window(base, headers, ep, lo, hi, min_span, cap, unresolved, extra, after_key, before_key)
        out.extend(rows); w += 1
        print("      " + ep + " window " + _win_fmt(lo)[:10] + ".." + _win_fmt(hi)[:10]
              + ": " + str(len(rows)) + " rows (" + str(len(out)) + " total across " + str(w) + " windows)")
        log_ingest(ep, "WINDOW", rows=len(out), detail=_win_fmt(lo)[:10] + ".." + _win_fmt(hi)[:10])
        lo = hi
    if unresolved:
        print("  !!!! " + ep + ": " + str(len(unresolved)) + " WINDOW(S) UNRESOLVED at min span -- a "
              + "bulk-update/migration cluster the deep-offset 413 blocks. Rows in these spans are NOT "
              + "landed; raise history_floor past them or pull by id. Spans: " + str(unresolved[:8]))
    return out
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
    ("appointments",                     "appointments",          "txn", t_appointment),
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
    (r'''import struct, pyodbc, uuid as _uuidlib
if not run_uuid:
    run_uuid = str(_uuidlib.uuid4())
_lcur = None
try:
    import sempy.fabric as _fab
    _wsid = _fab.get_workspace_id()
    _whs  = _fab.FabricRestClient().get(f"/v1/workspaces/{_wsid}/warehouses").json()["value"]
    _ep   = next((w["properties"]["connectionString"] for w in _whs if w["displayName"] == "WH_Dentally"), None)
    _tb   = notebookutils.credentials.getToken("https://database.windows.net/").encode("UTF-16-LE")
    _ts   = struct.pack(f"<I{len(_tb)}s", len(_tb), _tb)
    _lconn = pyodbc.connect("Driver={ODBC Driver 18 for SQL Server};Server=" + _ep + ",1433;Database=WH_Dentally;Encrypt=yes;TrustServerCertificate=no;", attrs_before={1256: _ts})
    _lconn.autocommit = True
    _lcur = _lconn.cursor()
    print("ingest-log -> Audit.Ingest_Log (run_uuid " + run_uuid + ")")
except Exception as _e:
    print("ingest-log DISABLED (cell output only):", str(_e)[:200])

_LOG_TID = None
def log_ingest(entity, phase, rows=None, detail=None):
    print("  [" + phase + "] " + str(entity) + (" rows=" + str(rows) if rows is not None else "") + ((" " + str(detail)) if detail else ""))
    if _lcur is None:
        return
    try:
        _lcur.execute(
            "INSERT INTO Audit.Ingest_Log (Run_UUID, Tenant_ID, Entity, Phase, Rows_Landed, Detail, Logged_At) VALUES (?,?,?,?,?,?,SYSUTCDATETIME())",
            run_uuid, (int(_LOG_TID) if _LOG_TID is not None else None), str(entity)[:100], str(phase)[:20], rows, (str(detail)[:1000] if detail is not None else None))
    except Exception:
        pass

# --- per-entity, per-tenant Bronze high-watermark (replaces the old blanket 24h lookback) --------
# Each incremental (txn) entity pulls updated_after = MAX(Updated_At already consumed by Bronze for
# THIS tenant) minus a 4h overlap, so a missed/failed run self-heals (next cutoff is simply older).
# Only entities whose Bronze table stores Updated_At are listed; accounts/payments/recalls have none
# so they full-pull each run (recalls is delete-heavy by design). Cold start (no Bronze rows yet)
# falls back to history_floor (windowed) for the big tables, else a plain full pull.
# WM entry: (Bronze table, Bronze column, API filter param, kind). kind "dt" = an updated_at
# datetime column filtered by updated_after (4h overlap); kind "d" = a DATE column filtered by a
# date param -- payments is strictly transactional (no updates) so it keys on dated_on/dated_after
# with a 1-day overlap. Entities not listed have no usable Bronze timestamp -> full-pull each run
# (accounts has no date column; recalls is delete-heavy by design; appointments Bronze lacks
# Updated_At -- needs it adding through the transform before it can be watermarked).
WM = {
    "patients":               ("Patients",               "Updated_At", "updated_after", "dt"),
    "appointments":           ("Appointments",           "Updated_At", "updated_after", "dt"),
    "invoices":               ("Invoices",               "Updated_At", "updated_after", "dt"),
    "invoice_items":          ("Invoice_Items",          "Updated_At", "updated_after", "dt"),
    "treatment_plans":        ("Treatment_Plans",        "Updated_At", "updated_after", "dt"),
    "treatment_plan_items":   ("Treatment_Plan_Items",   "Updated_At", "updated_after", "dt"),
    "treatment_appointments": ("Treatment_Appointments", "Updated_At", "updated_after", "dt"),
    "nhs_claims":             ("NHS_Claims",             "Updated_At", "updated_after", "dt"),
    "patient_referrals":      ("Patient_Referrals",      "Updated_At", "updated_after", "dt"),
    "payments":               ("Payments",               "Dated_On",   "dated_after",   "d"),
}
WM_OVERLAP_HOURS = 4
# Per-entity extra query params merged into every appointments pull. cancelled=true is REQUIRED or
# the API omits cancelled/DNA appointments -> a cancellation (an UPDATE) would never reach the delta.
PULL_EXTRA = {"appointments": {"cancelled": "true"}}
def bronze_watermark(tenant_id, stage_name):
    if full_refresh:                 # onboarding / forced full -> no watermark (cold path)
        return None
    if stage_name not in WM:         # no usable Bronze timestamp -> full pull (accounts / recalls)
        return None
    tbl, col, param, kind = WM[stage_name]
    if updated_after:                # explicit param = manual override; honour the entity's filter
        return {param: (updated_after[:10] if kind == "d" else updated_after)}
    if _lcur is None:
        return None
    cast = "date" if kind == "d" else "datetime2(3)"
    try:
        _lcur.execute("SELECT MAX(TRY_CAST([" + col + "] AS " + cast + ")) FROM Bronze.[" + tbl + "] WHERE Tenant_ID = ?", int(tenant_id))
        row = _lcur.fetchone()
        mx = row[0] if row and row[0] is not None else None
        if mx is None:
            return None
        if kind == "d":
            return {param: (mx - timedelta(days=1)).strftime("%Y-%m-%d")}
        return {param: (mx - timedelta(hours=WM_OVERLAP_HOURS)).strftime("%Y-%m-%dT%H:%M:%S")}
    except Exception as _e:
        print("  watermark read failed " + stage_name + ": " + str(_e)[:120])
        return None

for tid, cfg in TOKENS.items():
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
    _LOG_TID = tid
    for ep, stage_name, kind, fn in run_list:
        try:  # one bad/absent endpoint must not abort the whole practice's ingest
            log_ingest(ep, "START")
            if kind == "one":
                raw_rows = [fetch_one(base, headers, ep)]
            elif kind == "win":
                raw_rows = fetch_all(base, headers, ep, WINDOW, max_pages=cap)
            elif kind == "txn":
                extra = PULL_EXTRA.get(stage_name, {})                 # e.g. appointments -> cancelled=true
                wm = bronze_watermark(tid, stage_name)
                if wm is not None:                                     # WARM -> incremental from watermark
                    params = dict(wm); params.update(extra)
                    log_ingest(ep, "DELTA", detail=str(params))
                    raw_rows = fetch_all(base, headers, ep, params, max_pages=cap)
                elif ep == "appointments":                             # COLD: appointments date-window
                    # appointments ignores updated_before -> can't tile on updated_at. Window by start_time
                    # (after/before) from APPT_FLOOR to APPT_CEILING (even, shallow, includes future).
                    log_ingest(ep, "COLD", detail="date-window " + APPT_FLOOR[:10] + ".." + APPT_CEILING[:10])
                    raw_rows = fetch_windowed(base, headers, ep, APPT_FLOOR, APPT_CEILING,
                                              step_days=window_days, cap=cap, extra=extra,
                                              after_key="after", before_key="before")
                elif history_floor and ep in HISTORY_FLOOR_ENTITIES:   # COLD + big -> window from floor
                    log_ingest(ep, "COLD", detail="window from " + history_floor)
                    raw_rows = fetch_windowed(base, headers, ep, history_floor, load_timestamp,
                                              step_days=window_days, cap=cap, extra=extra)
                else:                                                  # COLD + small / no watermark -> full
                    raw_rows = fetch_all(base, headers, ep, dict(extra), max_pages=cap)
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
            log_ingest(ep, "DONE", rows=len(main))
        except Exception as e:
            print("  SKIP " + ep + ": " + str(e)[:200])
            log_ingest(ep, "SKIP", detail=str(e)[:200])

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
