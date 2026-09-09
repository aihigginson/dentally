"""
build_Sync_Subscriptions.py -- generator for Sync_Subscriptions.ipynb (Fabric).
Edit THIS, run `python build_Sync_Subscriptions.py` to regenerate the notebook.
Never hand-edit the .ipynb JSON (corrupts it); source is a list-of-lines.

Purpose: run Meta.usp_Sync_Access_From_AppDB (AppDB subscriptions -> WH Security.*) on the
hourly schedule, in WHICHEVER workspace the notebook runs in.

WHY A NOTEBOOK AND NOT A SCRIPT ACTIVITY. The pipeline previously ran this proc through a
Script activity bound to a NAMED CONNECTION. A named connection does not repoint when a
pipeline is promoted dev->prod (RUNBOOK golden rule 2, the same trap as the semantic-model
source), so the PROD pipeline ran happily against the DEV warehouse for weeks: prod's
Security.Application_Users kept 61 stale no_access rows while dev stayed clean, and no
subscription change ever reached prod. Nothing in the run history looked wrong, because the
run genuinely succeeded -- against the wrong database.

Resolving the warehouse from fabric.get_workspace_id() removes the connection entirely, so
the notebook is environment-agnostic and the dev and prod definitions stay IDENTICAL. Same
pattern as Orchestrate_Build / Orchestrate_Onboarding, which is exactly why the nightly
build was never affected.
"""
import json
import os

CELLS = [
    # 0 -- parameters ----------------------------------------------------------
    (r'''# Parameters -- Fabric overrides at runtime.
warehouse_name = "WH_Dentally"   # resolved IN THIS WORKSPACE, so dev and prod need no edit
''', True),

    # 1 -- connect to this workspace's warehouse -------------------------------
    (r'''import struct
import pyodbc
import sempy.fabric as fabric

# Follow the workspace: resolve the warehouse that lives alongside this notebook, so the SAME
# notebook targets dev on dev and prod on prod, with no connection object to repoint.
_ws_id = fabric.get_workspace_id()
_ws_nm = fabric.FabricRestClient().get("/v1/workspaces/" + _ws_id).json()["displayName"]
_whs   = fabric.FabricRestClient().get("/v1/workspaces/" + _ws_id + "/warehouses").json()["value"]
_wh    = next((w for w in _whs if w["displayName"] == warehouse_name), None)
if _wh is None:
    raise RuntimeError("Warehouse '" + warehouse_name + "' not found in workspace " + _ws_nm)
endpoint = _wh["properties"]["connectionString"]

_tok    = mssparkutils.credentials.getToken("https://database.windows.net/")
_tb     = _tok.encode("UTF-16-LE")
_struct = struct.pack("<I" + str(len(_tb)) + "s", len(_tb), _tb)
conn = pyodbc.connect(
    "Driver={ODBC Driver 18 for SQL Server};Server=" + endpoint + ",1433;Database=" + warehouse_name
    + ";Encrypt=yes;TrustServerCertificate=no;", attrs_before={1256: _struct})
conn.autocommit = True
cur = conn.cursor()
print("workspace '" + _ws_nm + "' -> " + endpoint.split(".")[0])
''', False),

    # 2 -- run the sync --------------------------------------------------------
    (r'''# Meta.usp_Sync_Access_From_AppDB is an UPSERT plus a REVOKE delete: a user with no module
# and no Maintain_Targets holds no Security row at all (Security is the auth surface, so it
# carries access-holders ONLY -- see the proc's *02 history note).
# Count around the call rather than SELECTing the OUT params: a batch that EXECs a proc and
# then SELECTs leaves pyodbc on the proc's own result sets, so fetchone() raises instead of
# returning the counts. Before/after is what we actually care about anyway.
cur.execute("SELECT COUNT(*) FROM Security.Application_Users;")
before = cur.fetchone()[0]

cur.execute("DECLARE @i BIGINT, @u BIGINT, @d BIGINT; "
            "EXEC Meta.usp_Sync_Access_From_AppDB @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;")

cur.execute("SELECT COUNT(*) FROM Security.Application_Users;")
after = cur.fetchone()[0]
print("Security.Application_Users: " + str(before) + " -> " + str(after))

# Post-condition: Security must hold no access-less rows. Assert rather than trust, so a
# regression in the proc surfaces here instead of silently leaving stale auth rows behind.
cur.execute("""
SELECT COUNT(*) FROM Security.Application_Users
WHERE NOT (Access_Home=1 OR Access_Revenue=1 OR Access_Patient=1 OR Access_Schedule=1
        OR Access_Clinical=1 OR Access_NHS=1 OR Access_Day_Book=1 OR Access_Finance=1
        OR Access_My_Data=1 OR Access_Marketing=1 OR Maintain_Targets=1);
""")
leftover = cur.fetchone()[0]
print("access-less rows remaining: " + str(leftover))
if leftover:
    raise RuntimeError(
        str(leftover) + " row(s) in Security.Application_Users have no module and no admin. "
        "The proc only deletes rows that JOIN to an AppDB row, so these are orphans with no "
        "AppDB counterpart and need clearing by hand.")
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
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Sync_Subscriptions.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, indent=1); f.write("\n")
    return out


if __name__ == "__main__":
    print("Wrote", build())
