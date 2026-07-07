# =============================================================================
# Orchestrate_Build  --  nightly end-to-end build (DAG-driven)
# =============================================================================
# The overnight orchestrator. Instead of calling the hardcoded usp_Load_Bronze /
# usp_Load_All scripts, this reads the metadata DAG (Audit.Process_Config +
# Audit.Process_Dependency) and fires Audit.ETL_Run_Process for each job in
# dependency order, then refreshes the Power BI semantic model.
#
#   [opt] Stage ingest   Dentally API -> Stage   (per tenant; off while Stage is seeded)
#   Bronze -> Silver -> Gold -> Agg              (DAG order; Bronze per tenant)
#   Semantic model refresh
#
# WHY DAG-driven: Audit.ETL_Run_Process is the atomic, self-logging executor for one
# registered job (resolves Process_Config, runs the SP, writes Audit.Process_Execution_Log).
# Driving it from Process_Dependency makes the ordering metadata (not a hardcoded SP) the
# single source of truth, and makes parallel execution a one-line change later (see
# run_wave: today max_parallel=1 / sequential; raise it + swap the loop for a
# ThreadPoolExecutor to fan out independent jobs within a wave).
#
# ERROR MODEL: ETL_Run_Process never raises -- it logs FAILED to Process_Execution_Log and
# returns. So this notebook reads the log after each job to get the status, and SKIPS any
# job whose upstream failed (dependency-aware). The semantic-model refresh is gated on a
# clean run. Targeted reruns of just the failed jobs: Audit.usp_Rerun_Failed_Jobs.
#
# Schema changes do NOT belong here -- they ride the Releases/Vnnn Deploy-Warehouse
# manifests. This pipeline only RUNS loads + refresh.
# =============================================================================


# -----------------------------------------------------------------------------
# CELL 1 - Parameters   (tag as a Parameters cell: ... -> Toggle parameter cell)
# -----------------------------------------------------------------------------

warehouse_sql_endpoint = ""            # leave BLANK -> auto-resolved from the current workspace (Cell 3); set only to override
warehouse_name         = "WH_Dentally" # same name in every workspace
semantic_model         = "DM Dentally" # same name in every workspace
workspace_name         = None          # None = the notebook's current workspace (so dev/prod are identical)
full_refresh           = False         # nightly = incremental (Bronze @Full_Refresh = 0)
run_stage_ingest       = False         # True = run Stage_Ingest (API->Stage) per tenant first; off while Stage is seeded out-of-band
refresh_semantic_model = True
refresh_settle_seconds = 180           # wait after the loads before refreshing the model: the SQL
                                       # endpoint lags the warehouse commit, so a refresh fired too
                                       # soon reads a not-yet-synced endpoint and publishes BLANK
                                       # measures (Gold is fine). ~3 min lets the endpoint catch up.
max_parallel           = 1             # V1: 1 = sequential within a wave. Future: >1 to fan out independent jobs.
tenants_override       = []            # e.g. [11, 12] to run a subset (testing/targeted); [] = all active tenants


# -----------------------------------------------------------------------------
# CELL 2 - Imports
# -----------------------------------------------------------------------------

import pyodbc
import struct
import time
from datetime import datetime, timezone
from collections import defaultdict


# -----------------------------------------------------------------------------
# CELL 3 - Connect to the Warehouse
# (standard Fabric pattern: mssparkutils token -> pyodbc access-token struct)
# -----------------------------------------------------------------------------

# Auto-resolve THIS workspace's warehouse SQL endpoint so the SAME notebook runs unchanged in
# every environment: in the dev workspace it finds the dev WH_Dentally, in prod the prod one.
# (Set warehouse_sql_endpoint in Cell 1 only to override.)
if not warehouse_sql_endpoint:
    import sempy.fabric as fabric
    _ws_id = fabric.get_workspace_id()
    _whs   = fabric.FabricRestClient().get(f"/v1/workspaces/{_ws_id}/warehouses").json()["value"]
    _wh    = next((w for w in _whs if w["displayName"] == warehouse_name), None)
    if _wh is None:
        raise RuntimeError(f"Warehouse '{warehouse_name}' not found in workspace {_ws_id}")
    warehouse_sql_endpoint = _wh["properties"]["connectionString"]
    print(f"Resolved {warehouse_name} endpoint from workspace {_ws_id}")

token        = mssparkutils.credentials.getToken("https://database.windows.net/")
token_bytes  = token.encode("UTF-16-LE")
token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)

conn_str = (
    "Driver={ODBC Driver 18 for SQL Server};"
    f"Server={warehouse_sql_endpoint},1433;"
    f"Database={warehouse_name};"
    "Encrypt=yes;TrustServerCertificate=no;"
)
conn = pyodbc.connect(conn_str, attrs_before={1256: token_struct})
conn.autocommit = True          # REQUIRED for Fabric: no explicit commit; DML autocommits
cursor = conn.cursor()
print(f"Connected to {warehouse_name} @ {warehouse_sql_endpoint}")


def q_all(sql, *params):
    cursor.execute(sql, *params) if params else cursor.execute(sql)
    return cursor.fetchall()

def q_scalar(sql, *params):
    cursor.execute(sql, *params) if params else cursor.execute(sql)
    row = cursor.fetchone()
    return row[0] if row else None


# -----------------------------------------------------------------------------
# CELL 4 - Load the metadata DAG (jobs, dependencies, tenants)
# -----------------------------------------------------------------------------

# Jobs: code -> (name, category, is_per_tenant).  Per-tenant jobs carry the {TID}
# token in their Process_Parameters (Bronze); everything else runs once.
job_rows = q_all("""
    SELECT Process_Code, Process_Name, Process_Category_Code, Process_Parameters
    FROM   Audit.Process_Config
""")
job_name     = {r[0]: r[1] for r in job_rows}
job_category = {r[0]: r[2] for r in job_rows}
per_tenant   = {r[0] for r in job_rows if r[3] and "{TID}" in r[3]}
all_codes    = set(job_name)

# Active dependency edges Prev -> Next (only between known jobs)
dep_rows = q_all("""
    SELECT Prev_Process_Code, Next_Process_Code
    FROM   Audit.Process_Dependency
    WHERE  Is_Active = 1
""")
prereqs   = defaultdict(set)   # code -> set of codes that must finish first
successors = defaultdict(set)
for prev, nxt in dep_rows:
    if prev in all_codes and nxt in all_codes:
        prereqs[nxt].add(prev)
        successors[prev].add(nxt)

# Active tenants (Bronze runs once per tenant). tenants_override scopes to a subset for testing.
tenants = [r[0] for r in q_all("SELECT Tenant_ID FROM Audit.Tenants WHERE Is_Active = 1 ORDER BY Tenant_ID")]
if tenants_override:
    tenants = [t for t in tenants if t in tenants_override]
if not tenants:
    raise RuntimeError("No active tenants to run (check Audit.Tenants / tenants_override)")

print(f"{len(all_codes)} jobs, {len(dep_rows)} dependency edges, {len(tenants)} tenant(s): {tenants}")


# -----------------------------------------------------------------------------
# CELL 5 - Topological "waves" (Kahn). Each wave = jobs whose prereqs are all done.
# -----------------------------------------------------------------------------

in_degree = {c: len(prereqs[c]) for c in all_codes}
ready     = sorted([c for c in all_codes if in_degree[c] == 0])
waves     = []
done      = set()

while ready:
    waves.append(ready)
    done.update(ready)
    nxt = set()
    for c in ready:
        for s in successors[c]:
            in_degree[s] -= 1
            if in_degree[s] == 0:
                nxt.add(s)
    ready = sorted(nxt)

if len(done) != len(all_codes):
    raise RuntimeError(f"Dependency cycle / unreachable jobs: {sorted(all_codes - done)}")

print(f"{len(waves)} waves: " + " | ".join(f"w{i}={len(w)}" for i, w in enumerate(waves)))


# -----------------------------------------------------------------------------
# CELL 6 - Start the parent run (groups all child ETL_Run_Process runs in Audit)
# -----------------------------------------------------------------------------

run_opts = f"@full_refresh={int(full_refresh)}, @stage_ingest={int(run_stage_ingest)}, @max_parallel={max_parallel}"

# ETL_Start_Run does an INSERT then SELECTs the new UUID. pyodbc surfaces the INSERT
# (a non-query) first, so we must WALK the result sets and read whichever one is a query.
# SET NOCOUNT ON suppresses the insert row-count; the walk handles it regardless.
cursor.execute(
    "SET NOCOUNT ON; "
    "DECLARE @id VARCHAR(36); "
    "EXEC Audit.ETL_Start_Run @Run_Process_Name=?, @Run_Process_Options=?, @Run_UUID=@id OUTPUT, @Process_Type='PROCEDURE'; "
    "SELECT @id AS run_uuid;",
    "Audit.Orchestrate_Build", run_opts
)
parent_uuid = None
while True:
    if cursor.description is not None:          # current result set is a row-returning query
        r = cursor.fetchone()
        if r and r[0]:
            parent_uuid = r[0]
    if not cursor.nextset():
        break
if not parent_uuid:
    raise RuntimeError("Could not obtain parent run UUID from ETL_Start_Run")
print(f"Parent run: {parent_uuid}")


# -----------------------------------------------------------------------------
# CELL 7 - (optional) Stage ingest: Dentally API -> Stage, per tenant
# Off by default (prod/dev Stage is seeded out-of-band today). Turn on when the
# real Dentally extract is wired.
# -----------------------------------------------------------------------------

if run_stage_ingest:
    for tid in tenants:
        print(f"Stage_Ingest tenant {tid} ...")
        mssparkutils.notebook.run("Stage_Ingest", 1200, {"tenant_id": tid, "full_refresh": full_refresh})
    time.sleep(30)   # let lakehouse metadata propagate to the SQL engine before Bronze reads Stage


# -----------------------------------------------------------------------------
# CELL 8 - Fire one job via ETL_Run_Process, then read its status from the log.
# (ETL_Run_Process swallows errors -> we must read Process_Execution_Log.)
# -----------------------------------------------------------------------------

def fire(code, tenant_id=None):
    """Run one process (optionally for one tenant); return ('SUCCEEDED'|'FAILED'|None, error)."""
    name = job_name[code]
    if tenant_id is None:
        cursor.execute("SET NOCOUNT ON; EXEC Audit.ETL_Run_Process @Process_Code=?, @Parent_Run_UUID=?", code, parent_uuid)
    else:
        cursor.execute(
            "SET NOCOUNT ON; EXEC Audit.ETL_Run_Process @Process_Code=?, @Parent_Run_UUID=?, @Tenant_ID=?, @Full_Refresh=?",
            code, parent_uuid, tenant_id, int(full_refresh)
        )
    while cursor.nextset():   # drain ETL_Run_Process's nested result sets (it calls ETL_Start_Run)
        pass
    # latest run for this proc under our parent = the one we just fired (sequential).
    row = q_all(
        "SELECT TOP 1 Status, Error_Message FROM Audit.Process_Execution_Log "
        "WHERE Parent_Run_UUID = ? AND Process_Name = ? ORDER BY Start_Time DESC",
        parent_uuid, name
    )
    return (row[0][0], row[0][1]) if row else (None, "no log row")


def run_job(code):
    """Run a job (looping tenants for per-tenant Bronze); True if all parts succeeded."""
    if code in per_tenant:
        ok = True
        for tid in tenants:
            status, err = fire(code, tid)
            if status != "SUCCEEDED":
                ok = False
                print(f"    FAILED {code} (tenant {tid}): {err}")
        return ok
    status, err = fire(code)
    if status != "SUCCEEDED":
        print(f"    FAILED {code}: {err}")
    return status == "SUCCEEDED"


# -----------------------------------------------------------------------------
# CELL 9 - Execute the waves. Skip any job whose upstream failed.
# V1 is sequential within a wave; to parallelise later, run this inner loop on a
# ThreadPoolExecutor(max_parallel) with a *separate pyodbc connection per worker*.
# -----------------------------------------------------------------------------

failed   = set()    # failed OR blocked-by-upstream-failure
skipped  = set()
ok_codes = set()

for i, wave in enumerate(waves):
    print(f"\n=== Wave {i} ({len(wave)} jobs) ===")
    for code in wave:
        blocked = prereqs[code] & failed
        if blocked:
            failed.add(code); skipped.add(code)
            print(f"  SKIP {code} (upstream failed: {sorted(blocked)})")
            continue
        tag = " (per-tenant)" if code in per_tenant else ""
        print(f"  RUN  {code}{tag}")
        if run_job(code):
            ok_codes.add(code)
        else:
            failed.add(code)

real_failures = failed - skipped


# -----------------------------------------------------------------------------
# CELL 10 - Close the parent run
# -----------------------------------------------------------------------------

final_status = "SUCCEEDED" if not failed else "FAILED"
cursor.execute("EXEC Audit.ETL_Finish_Run @Run_UUID=?, @Run_Status=?", parent_uuid, final_status)
print(f"\nParent run {parent_uuid}: {final_status}")


# -----------------------------------------------------------------------------
# CELL 11 - Refresh the semantic model (only on a clean build)
# -----------------------------------------------------------------------------

if refresh_semantic_model and not failed:
    import sempy.fabric as fabric
    # SQL-endpoint sync lag: the endpoint the model reads trails the warehouse commit, so refreshing
    # immediately after the loads can publish a BLANK model (measures empty though Gold is populated).
    # Wait for the endpoint to catch up before refreshing. See reference_sql_endpoint_refresh_lag.
    print(f"Settling {refresh_settle_seconds}s for the SQL endpoint before refresh ...")
    time.sleep(refresh_settle_seconds)
    print(f"Refreshing semantic model '{semantic_model}' ...")
    # Triggers an enhanced refresh. NOTE: confirm your sempy version blocks until done;
    # if not, poll fabric.list_refresh_requests(...) until the latest request completes,
    # or use the pipeline's native "Semantic model refresh" activity instead.
    fabric.refresh_dataset(dataset=semantic_model, workspace=workspace_name)
    print("Refresh requested.")
elif failed:
    print("Skipping semantic-model refresh: build had failures.")


# -----------------------------------------------------------------------------
# CELL 12 - Summary  (raise on failure so the schedule flags the run)
# -----------------------------------------------------------------------------

print("\n" + "=" * 60)
print(f"Build complete: {len(ok_codes)} ok, {len(real_failures)} failed, {len(skipped)} skipped")
if real_failures:
    print(f"  Failed : {sorted(real_failures)}")
if skipped:
    print(f"  Skipped: {sorted(skipped)}")
print("Rerun just the failed jobs with: EXEC Audit.usp_Rerun_Failed_Jobs (dependency-aware).")
print("=" * 60)

if failed:
    raise RuntimeError(f"Overnight build failed: {len(real_failures)} failed, {len(skipped)} skipped")


# -----------------------------------------------------------------------------
# CELL 13 - Release the Spark session immediately on a clean build, so the run
#           doesn't sit idle until the session timeout after completing (the
#           "hangs around"). On failure CELL 12 raises above, so this runs only
#           on success. notebookutils is the current Fabric API; on older
#           runtimes use mssparkutils.session.stop() instead.
# -----------------------------------------------------------------------------

print("Build done -- stopping the Spark session to release compute now.")
notebookutils.session.stop()
