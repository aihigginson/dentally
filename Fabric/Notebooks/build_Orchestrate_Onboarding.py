"""
build_Orchestrate_Onboarding.py -- generator for Orchestrate_Onboarding.ipynb (Fabric).
Edit THIS, run `python build_Orchestrate_Onboarding.py` to regenerate. Never hand-edit the .ipynb.

Orchestrate_Onboarding (design: .claude/plans/onboarding-delta-build-architecture.md) -- a forced
single-tenant, from-the-top build for onboarding a real practice or rebuilding one from the frozen
snapshot. It does NOT branch full-vs-delta; the clean slate comes from the pre-clear.

  STEP 1  clear      Audit.usp_Clear_Tenant_Data (data-only; keeps registration/RLS/targets/config)
  STEP 2  populate   source=api    -> Ingest_Dentally FULL pull (tpi/plans date-windowed)
                     source=frozen -> Freeze_Onboarding_Stage restore (init_stage_* -> stage_*)
  STEP 3  build      Orchestrate_Build build-only (run_stage_ingest=False) -> Bronze..Gold + refresh
  ( STEP 4 freeze )  NOT automatic. Validate Gold first, THEN run Freeze_Onboarding_Stage
                     (direction=freeze) -- "ingest can succeed with wrong data; don't freeze until
                     Gold looks right". api source only.

Reuses Orchestrate_Build as the build engine (one build DAG, no fork). Synthetic T11/T12 never use
this (seed_onelake -> Orchestrate_Build build-only).
"""
import json
import os

CELLS = [
    # 0 -- parameters ----------------------------------------------------------
    (r'''# Parameters -- Fabric overrides at runtime.
tenant_id      = 100          # the ONE practice to onboard/rebuild (forced single-tenant)
source         = "api"        # "api" = full Dentally pull ; "frozen" = restore from init_stage_*
history_floor  = "2021-01-01T00:00:00Z"   # updated_after floor for the huge historical tables
window_days    = 30           # date-window size for the tpi/treatment_plans deep-offset 413
dentally_env   = "dev"        # dentally-tokens-<env> (dev|prod)
warehouse_name = "WH_Dentally"
ingest_timeout = 21600        # s -- a full onboarding pull is multi-hour (rate-limited to 3600/hr)
build_timeout  = 7200         # s -- Bronze..Gold + model refresh
refresh_model  = True         # refresh the semantic model at the end of the build
''', True),

    # 1 -- connect to the warehouse (for the clear) ----------------------------
    (r'''import struct, time
import pyodbc

# Auto-resolve THIS workspace's warehouse endpoint so the notebook is identical in dev/prod.
import sempy.fabric as fabric
_ws_id = fabric.get_workspace_id()
_whs   = fabric.FabricRestClient().get("/v1/workspaces/" + _ws_id + "/warehouses").json()["value"]
_wh    = next((w for w in _whs if w["displayName"] == warehouse_name), None)
if _wh is None:
    raise RuntimeError("Warehouse '" + warehouse_name + "' not found in workspace " + _ws_id)
endpoint = _wh["properties"]["connectionString"]

_tok    = mssparkutils.credentials.getToken("https://database.windows.net/")
_tb     = _tok.encode("UTF-16-LE")
_struct = struct.pack("<I" + str(len(_tb)) + "s", len(_tb), _tb)
conn = pyodbc.connect(
    "Driver={ODBC Driver 18 for SQL Server};Server=" + endpoint + ",1433;Database=" + warehouse_name
    + ";Encrypt=yes;TrustServerCertificate=no;", attrs_before={1256: _struct})
conn.autocommit = True
cur = conn.cursor()
print("ONBOARDING tenant " + str(tenant_id) + " | source=" + source + " | env=" + dentally_env)
print("Connected to " + warehouse_name + " @ " + endpoint)
''', False),

    # 2 -- STEP 1: clear -------------------------------------------------------
    (r'''print("\nSTEP 1/3  CLEAR tenant " + str(tenant_id) + " (data only; config/RLS/targets preserved)")
cur.execute("SET NOCOUNT ON; EXEC Audit.usp_Clear_Tenant_Data @Tenant_ID = ?", tenant_id)
while cur.nextset():
    pass
print("  cleared.")
''', False),

    # 3 -- STEP 2: populate stage ----------------------------------------------
    (r'''print("\nSTEP 2/3  POPULATE stage (source=" + source + ")")
if source == "api":
    # Full pull; tpi/treatment_plans are date-windowed inside Ingest_Dentally (deep-offset 413).
    mssparkutils.notebook.run("Ingest_Dentally", ingest_timeout, {
        "only_tenant":   str(tenant_id),
        "full_refresh":  True,
        "history_floor": history_floor,
        "window_days":   window_days,
        "dentally_env":  dentally_env,
    })
elif source == "frozen":
    # Restore the frozen onboarding snapshot back into stage_* (no API call).
    mssparkutils.notebook.run("Freeze_Onboarding_Stage", build_timeout, {
        "tenant_id": str(tenant_id),
        "direction": "restore",
    })
else:
    raise ValueError("source must be 'api' or 'frozen', got: " + repr(source))
time.sleep(30)   # let lakehouse metadata propagate to the SQL engine before Bronze reads Stage
print("  stage populated.")
''', False),

    # 4 -- STEP 3: build -------------------------------------------------------
    (r'''print("\nSTEP 3/3  BUILD Bronze..Gold (build-only; stage already populated)")
# run_stage_ingest=False -> build only (NOT a delta pull). full_refresh=False -> plain upsert; the
# tenant was just cleared so every row inserts fresh (DW_Updated_At=now), which the watermark facts
# pick up without a watermark reset. DEV has T100 as the only active tenant so no tenant scoping is
# needed; PROD multi-tenant onboarding should scope the build to this tenant (see notebook docstring).
mssparkutils.notebook.run("Orchestrate_Build", build_timeout, {
    "run_stage_ingest":       False,
    "full_refresh":           False,
    "refresh_semantic_model": refresh_model,
})
print("  build complete.")
''', False),

    # 5 -- next step: validate then freeze -------------------------------------
    (r'''print("\n" + "=" * 66)
print("Onboarding build finished for tenant " + str(tenant_id) + ".")
print("NEXT (gated -- not automatic):")
print("  1) VALIDATE Gold looks right (Check_Stage_Duplicates.sql; scan the Ingest log for any")
print("     'WINDOW(S) UNRESOLVED'; spot-check counts + the reports).")
if source == "api":
    print("  2) THEN snapshot: run Freeze_Onboarding_Stage (tenant_id=" + str(tenant_id)
          + ", direction='freeze') so deltas can overwrite stage_* safely.")
else:
    print("  2) source=frozen -> no re-freeze needed (this WAS a restore from the snapshot).")
print("=" * 66)
conn.close()
''', False),
]


def build():
    cells = []
    for src, is_params in CELLS:
        cells.append({
            "cell_type": "code",
            "execution_count": None,
            "metadata": {"tags": ["parameters"]} if is_params else {},
            "outputs": [],
            "source": src.splitlines(keepends=True),
        })
    nb = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4, "nbformat_minor": 4,
    }
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Orchestrate_Onboarding.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, indent=1); f.write("\n")
    return out


if __name__ == "__main__":
    print("Wrote", build())
