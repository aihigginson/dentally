"""
build_Generate_Invoices.py -- generator for Generate_Invoices.ipynb (Fabric).
Edit THIS, run `python build_Generate_Invoices.py` to regenerate the notebook.
Never hand-edit the .ipynb JSON (corrupts it); source is a list-of-lines.

Purpose: run Billing.usp_Generate_Invoice_Lines in WHICHEVER workspace the notebook runs in.
Triggered by hand (no schedule), at the point invoices are raised for a period.

Same fix as Sync_Subscriptions: the pipeline previously used a Script activity bound to a
NAMED CONNECTION, which does not repoint on dev->prod promotion (RUNBOOK golden rule 2). The
result was that running Generate_Invoices on PROD wrote its invoice lines into the DEV
warehouse -- prod's Billing.Invoice_Line was still empty while dev held 17 rows belonging to
a prod tenant. Resolving the warehouse from the workspace removes the connection, so the dev
and prod definitions are identical and each lands in its own environment.
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

    # 2 -- generate the invoice lines ------------------------------------------
    (r'''cur.execute("SELECT COUNT(*) FROM Billing.Invoice_Line;")
before = cur.fetchone()[0]

cur.execute("EXEC Billing.usp_Generate_Invoice_Lines;")

cur.execute("SELECT COUNT(*) FROM Billing.Invoice_Line;")
after = cur.fetchone()[0]
print("Billing.Invoice_Line: " + str(before) + " -> " + str(after) + "  (+" + str(after - before) + ")")

# Show what the run produced, so a hand-triggered invoice run is auditable from the output.
cur.execute("""
SELECT TOP 20 Tenant_ID, Year_Month, COUNT(*) AS lines, SUM(Value) AS value
FROM Billing.Invoice_Line
GROUP BY Tenant_ID, Year_Month
ORDER BY Year_Month DESC, Tenant_ID;
""")
for r in cur.fetchall():
    print("  tenant " + str(r[0]) + "  " + str(r[1]) + "  lines=" + str(r[2]) + "  value=" + str(r[3]))
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
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Generate_Invoices.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, indent=1); f.write("\n")
    return out


if __name__ == "__main__":
    print("Wrote", build())
