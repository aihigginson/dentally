"""
build_Orchestrate_Onboarding.py -- generator for Orchestrate_Onboarding.ipynb (Fabric).
Edit THIS, run `python build_Orchestrate_Onboarding.py` to regenerate. Never hand-edit the .ipynb.

Orchestrate_Onboarding (design: .claude/plans/onboarding-delta-build-architecture.md) -- a forced
single-tenant, from-the-top build for onboarding a real practice or rebuilding one from the frozen
snapshot. No full-vs-delta branching; the clean slate comes from the pre-clear.

  STEP 1  clear      Audit.usp_Clear_Tenant_Data (data only; keeps registration/RLS/targets/config)
  STEP 2  populate   source=api    -> Ingest_Dentally FULL pull (tpi/plans date-windowed)
                     source=frozen -> Freeze_Onboarding_Stage restore (init_stage_* -> stage_*)
  STEP 3  freeze     (api only) snapshot stage_* -> init_stage_* NOW -- captures the expensive pull
                     immediately (unattended, non-destructive, overwrite-able), and its Spark copy
                     runtime doubles as free settle time for the SQL endpoint.
  STEP 4  settle     POLL the warehouse SQL endpoint until it can see THIS run's new stage rows.
                     Bronze reads Stage.* via SQL and the endpoint lags the Spark write -- last time
                     a fixed 30s wait was too short and the whole build loaded 0 rows. This is
                     deterministic: it waits exactly until the data is visible, then no longer.
  STEP 5  build      Orchestrate_Build build-only (run_stage_ingest=False) -> Bronze..Gold + refresh.

Freeze is api-only (frozen IS a restore). Validate Gold before you TRUST a source=frozen restore.
Synthetic T11/T12 never use this (seed_onelake -> Orchestrate_Build build-only).
"""
import json
import os

CELLS = [
    # 0 -- parameters ----------------------------------------------------------
    (r'''# Parameters -- Fabric overrides at runtime.
tenant_id      = 100          # the ONE practice to onboard/rebuild (single-tenant; set by STEP 0 when onboard_from_pending)
onboard_from_pending = False  # True: STEP 0 provisions the next self-serve signup (KV onboarding-pending-<env>) + moves its token
pending_key          = ""     # which pending entry to provision (the store key from the owner-notify email); "" = the single one waiting
source         = "api"        # "api" = full Dentally pull ; "frozen" = restore from init_stage_*
history_floor  = "2021-01-01T00:00:00Z"   # updated_after floor for the huge historical tables
window_days    = 30           # date-window size for the tpi/treatment_plans deep-offset 413
dentally_env   = "dev"        # dentally-tokens-<env> (dev|prod)
warehouse_name = "WH_Dentally"
ingest_timeout = 36000        # s -- a full onboarding pull is multi-hour (rate-limited to 3600/hr)
build_timeout  = 14400        # s -- Bronze..Gold + model refresh
refresh_model  = True         # refresh the semantic model at the end of the build
freeze_after_pull    = True   # api only: snapshot stage->init_stage right after the pull
sync_poll_seconds    = 30     # how often to poll the SQL endpoint for the new stage
sync_timeout_seconds = 2400   # give up (raise, don't build empty) if it hasn't synced in this long
stage_sync_tables    = ["Patients", "Treatment_Plan_Items", "Treatment_Appointments"]  # poll these
''', True),

    # 1 -- connect + run marker ------------------------------------------------
    (r'''import struct, time
from datetime import datetime, timezone
import pyodbc

# run_start: captured BEFORE the pull. The pull stamps every stage row DW_Stage_Loaded_At at its
# own (later) start, and the restore re-stamps too, so ">= run_start" reliably detects THIS run's
# stage write appearing through the SQL endpoint (not stale prior data).
run_start = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

import sempy.fabric as fabric
_ws_id = fabric.get_workspace_id()
# Follow the workspace: a non-DEV workspace name => prod token set, so the SAME notebook
# onboards on dev or prod with no per-promotion edit (matches Orchestrate_Build).
_ws_nm = fabric.FabricRestClient().get("/v1/workspaces/" + _ws_id).json()["displayName"]
if "DEV" not in _ws_nm.upper():
    dentally_env = "prod"
print("Env follows workspace '" + _ws_nm + "': dentally_env=" + dentally_env)
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
print("ONBOARDING tenant " + str(tenant_id) + " | source=" + source + " | env=" + dentally_env
      + " | run_start=" + run_start)
print("Connected to " + warehouse_name + " @ " + endpoint)
''', False),

    # 1b -- STEP 0: provision the pending signup + MOVE its token into KV ------
    (r'''print("\nSTEP 0  PROVISION next self-serve signup" if onboard_from_pending
      else "\nSTEP 0  rebuild existing tenant " + str(tenant_id) + " (no pending provision)")
if onboard_from_pending:
    import json, requests
    keyvault_url   = "https://kv-analytically.vault.azure.net/"
    pending_secret = "onboarding-pending-" + dentally_env
    tokens_secret  = "dentally-tokens-" + dentally_env

    def kv_get(name):
        return mssparkutils.credentials.getSecret(keyvault_url, name)

    def kv_json(name):
        raw = (kv_get(name) or "").lstrip("﻿").strip()
        return json.loads(raw) if raw else {}

    def _vault_token():
        # cell 1 proves getToken accepts a resource URL; try the KV resource forms so a naming
        # difference in the runtime doesn't sink the write.
        for aud in ("https://vault.azure.net", "https://vault.azure.net/", "keyvault"):
            try:
                t = mssparkutils.credentials.getToken(aud)
                if t:
                    return t
            except Exception:
                pass
        raise RuntimeError("could not acquire a Key Vault token (getToken); grant the run identity KV access")

    def kv_set(name, value):
        # notebookutils/mssparkutils can READ a secret but not write one, so PUT via the Key Vault
        # REST API with a vault-scoped token. The running identity (workspace / pipeline) must have
        # secrets 'set' on kv-analytically (it already needs 'get' for the ingest).
        r = requests.put(keyvault_url.rstrip("/") + "/secrets/" + name + "?api-version=7.4",
                         headers={"Authorization": "Bearer " + _vault_token(), "Content-Type": "application/json"},
                         json={"value": value}, timeout=30)
        r.raise_for_status()

    pend = kv_json(pending_secret)
    # Pick the signup to provision: an explicit key (from the owner-notify email), else the single
    # entry still awaiting provisioning. Refuse to guess when several are waiting.
    if pending_key:
        if pending_key not in pend:
            raise RuntimeError("pending_key '" + pending_key + "' not found in " + pending_secret
                               + " (keys: " + str(list(pend.keys())) + ")")
        key = pending_key
    else:
        waiting = sorted((v.get("created_at", ""), k) for k, v in pend.items()
                         if v.get("status") == "pending_provision")
        if not waiting:
            raise RuntimeError("No entries with status 'pending_provision' in " + pending_secret)
        if len(waiting) > 1:
            raise RuntimeError("Several signups are waiting -- pass pending_key. Waiting: "
                               + str([k for _, k in waiting]))
        key = waiting[0][1]

    e   = pend[key]
    pat = e.get("personal_access_token") or (e.get("oauth") or {}).get("access_token")
    if not pat:
        raise RuntimeError("Pending entry '" + key + "' carries no token (auth_method="
                           + str(e.get("auth_method")) + ")")
    print("  signup: practice=" + str(e.get("practice_name"))
          + " principal=" + str(e.get("principal_email")) + " key=" + key)

    # 1) Provision the tenant config (allocates Tenant_ID/Client_ID + access chain + trial billing;
    #    idempotent on the principal email -- a re-run returns the existing tenant, no duplicates).
    _sql = ("DECLARE @t INT; "
            "EXEC Audit.usp_Provision_Tenant @Practice_Name=?, @Principal_Email=?, @Paid_From=?, "
            "@Dentally_Practice_ID=?, @Tenant_ID=@t OUTPUT; SELECT @t;")
    row = cur.execute(_sql, e.get("practice_name"), e.get("principal_email"),
                      e.get("paid_from"), str(e.get("dentally_practice_id") or "")).fetchone()
    tenant_id = int(row[0])
    while cur.nextset():
        pass
    print("  provisioned Tenant_ID=" + str(tenant_id))

    # 2) MOVE the token into dentally-tokens-<env>, keyed by the new Tenant_ID -- the exact shape
    #    Ingest_Dentally reads ({"<tid>": {"token","base_url","name"}}). The hand-off from the web
    #    capture to the ingest. (The token value is never printed.)
    toks = kv_json(tokens_secret)
    toks[str(tenant_id)] = {
        "base_url": e.get("base_url") or "https://api.dentally.co/v1",
        "name":     e.get("practice_name"),
        "token":    pat,
    }
    kv_set(tokens_secret, json.dumps(toks))
    print("  token moved -> " + tokens_secret + "[" + str(tenant_id) + "]")

    # 3) Mark the pending entry provisioned (kept for audit; the token now lives in dentally-tokens).
    e["status"]         = "provisioned"
    e["tenant_id"]      = tenant_id
    e["provisioned_at"] = datetime.utcnow().isoformat() + "Z"
    pend[key] = e
    kv_set(pending_secret, json.dumps(pend))
    print("  pending entry '" + key + "' -> provisioned.")
''', False),

    # 2 -- STEP 1: clear -------------------------------------------------------
    (r'''print("\nSTEP 1  CLEAR tenant " + str(tenant_id) + " (data only; config/RLS/targets preserved)")
cur.execute("SET NOCOUNT ON; EXEC Audit.usp_Clear_Tenant_Data @Tenant_ID = ?", tenant_id)
while cur.nextset():
    pass
print("  cleared.")
''', False),

    # 3 -- STEP 2: populate stage ----------------------------------------------
    (r'''print("\nSTEP 2  POPULATE stage (source=" + source + ")")
if source == "api":
    mssparkutils.notebook.run("Ingest_Dentally", ingest_timeout, {
        "only_tenant":   str(tenant_id),
        "full_refresh":  True,
        "history_floor": history_floor,
        "window_days":   window_days,
        "dentally_env":  dentally_env,
    })
elif source == "frozen":
    mssparkutils.notebook.run("Freeze_Onboarding_Stage", build_timeout, {
        "tenant_id": str(tenant_id),
        "direction": "restore",
    })
else:
    raise ValueError("source must be 'api' or 'frozen', got: " + repr(source))
print("  stage populated (Spark).")
''', False),

    # 4 -- STEP 3: freeze (api only) -------------------------------------------
    (r'''if source == "api" and freeze_after_pull:
    print("\nSTEP 3  FREEZE stage -> init_stage_* (snapshot the pull; also lets the endpoint settle)")
    mssparkutils.notebook.run("Freeze_Onboarding_Stage", build_timeout, {
        "tenant_id": str(tenant_id),
        "direction": "freeze",
    })
    print("  frozen -> init_stage_*.")
else:
    print("\nSTEP 3  freeze skipped (source=frozen, or freeze_after_pull=False)")
''', False),

    # 5 -- STEP 4: settle (poll the SQL endpoint) ------------------------------
    (r'''print("\nSTEP 4  wait for the SQL endpoint to surface THIS run's stage (Bronze reads Stage via SQL)")
def _new_rows(t):
    cur.execute("SELECT COUNT_BIG(*) FROM Stage." + t
                + " WHERE tenant_id = ? AND DW_Stage_Loaded_At >= ?", str(tenant_id), run_start)
    row = cur.fetchone()
    return int(row[0]) if row and row[0] is not None else 0

deadline = time.time() + sync_timeout_seconds
pending = list(stage_sync_tables)
while pending:
    still = []
    for t in pending:
        try:
            n = _new_rows(t)
        except Exception as e:
            n = 0; print("    (Stage." + t + " probe error: " + str(e)[:80] + ")")
        if n > 0:
            print("    synced Stage." + t + " (" + str(n) + " new rows)")
        else:
            still.append(t)
    pending = still
    if not pending:
        break
    if time.time() > deadline:
        raise RuntimeError("SQL endpoint did not surface new stage rows within "
                           + str(sync_timeout_seconds) + "s for " + str(pending)
                           + " -- build ABORTED to avoid loading an empty stage.")
    print("    still waiting on " + str(pending) + " (sleep " + str(sync_poll_seconds) + "s)")
    time.sleep(sync_poll_seconds)
print("  endpoint synced -- safe to build.")
''', False),

    # 6 -- STEP 5: build -------------------------------------------------------
    (r'''print("\nSTEP 5  BUILD Bronze..Gold (build-only; stage populated + endpoint synced)")
mssparkutils.notebook.run("Orchestrate_Build", build_timeout, {
    "full_refresh":           False,
    "refresh_semantic_model": refresh_model,
})
print("  build complete.")
''', False),

    # 6b -- STEP 6: set Cutover_Date + refresh capitation-gated Gold -----------
    (r'''print("\nSTEP 6  SET tenant Cutover_Date (MIN updated_at of Treatment Plans) + refresh capitation-gated Gold")
# Cutover_Date = the tenant's Dentally go-live (updated_at is stamped by Dentally, not migrated history).
# Single source of truth for downstream cutover logic (plan capitation, the ingest cold floor). Set it
# here, once the build has populated Silver.Treatment_Plans.
cur.execute("EXEC Audit.usp_Set_Tenant_Cutover @Tenant_ID = " + str(tenant_id))
cur.execute("SELECT Cutover_Date FROM Audit.Tenants WHERE Tenant_ID = " + str(tenant_id))
_row = cur.fetchone()
print("  Audit.Tenants.Cutover_Date = " + str(_row[0] if _row else None))

# Fact_Revenue's capitation half is gated on Cutover_Date, which was NULL during STEP 5's build (first
# onboarding of this tenant), so its capitation came out empty. Re-run it + the aggs that read it so
# capitation + target actuals are correct at the end of onboarding.
for _sp in ["Gold.usp_Load_Fact_Revenue",
            "Gold.usp_Load_Fact_Metric_Actuals",
            "Gold.usp_Load_Aggregate_Practitioner_Contribution"]:
    cur.execute("DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC " + _sp
                + " @Mode='PROD', @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;")
    print("  re-ran " + _sp)
cur.execute("EXEC Meta.usp_Create_Gold_Views")
print("  Gold views regenerated (capitation now from go-live only).")
''', False),

    # 7 -- done ----------------------------------------------------------------
    (r'''print("\n" + "=" * 66)
print("Onboarding complete for tenant " + str(tenant_id) + ".")
if source == "api" and freeze_after_pull:
    print("  Stage snapshot already frozen to init_stage_* (deltas may now overwrite stage_*).")
print("  VALIDATE Gold (Check_Stage_Duplicates.sql; scan the Ingest log for 'WINDOW(S) UNRESOLVED';")
print("  spot-check counts + reports). Then it's live for nightly deltas.")
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
