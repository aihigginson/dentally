"""
build_Promote_Tenant_Stage.py  --  Generator for Promote_Tenant_Stage.ipynb (Fabric notebook).

Edit THIS file, then run `python build_Promote_Tenant_Stage.py` to regenerate the notebook.
Never hand-edit the .ipynb (source must be a list-of-lines; manual edits have corrupted these).

One-off DEV->PROD promotion of a real practice WITHOUT re-hitting the Dentally API (option B):
copy the landed stage_* Delta tables for one tenant from the dev LH_Dentally to prod's, then
build Bronze->Gold in prod from the copied stage. Two modes in one notebook:

  mode="copy"  : RUN IN PROD (prod LH_Dentally attached as default). Reads the source (dev)
                 lakehouse's stage_* over OneLake and writes this tenant's rows into prod stage.
  mode="purge" : RUN IN DEV (dev LH_Dentally attached as default). DELETEs this tenant's rows
                 from every local stage_* table -- run AFTER prod is verified, so real data
                 doesn't linger in dev.

Surrounding warehouse steps (register tenant in prod Audit.Tenants; Orchestrate_Build with
run_dentally_ingest=False; usp_Delete_All_Tenant in dev) are in DENTALLY_ONBOARDING.md.
"""
import json
import os

CELLS = [
    # 0 -- parameters ----------------------------------------------------------
    (r'''# Parameters -- Fabric overrides these at runtime.
mode             = "copy"           # "copy" (run in PROD) | "purge" (run in DEV)
tenant_id        = 100              # the practice to promote / purge
source_workspace = ""               # COPY only: dev workspace NAME or GUID (where stage lives now)
source_lakehouse = "LH_Dentally"    # COPY only: source lakehouse display name
confirm_purge    = False            # PURGE only: must be True to actually delete
''', True),

    # 1 -- imports -------------------------------------------------------------
    (r'''import sempy.fabric as fabric
import mssparkutils
''', False),

    # 2 -- copy: dev stage -> prod stage (this tenant only) --------------------
    (r'''def do_copy():
    if not source_workspace:
        raise SystemExit("copy mode needs source_workspace (the dev workspace name or GUID).")
    src_ws_id = fabric.resolve_workspace_id(source_workspace)
    lhs = fabric.FabricRestClient().get(f"/v1/workspaces/{src_ws_id}/lakehouses").json()["value"]
    src_lh = next((l for l in lhs if l["displayName"] == source_lakehouse), None)
    if src_lh is None:
        raise SystemExit(f"Lakehouse {source_lakehouse} not found in workspace {source_workspace}")
    base = f"abfss://{src_ws_id}@onelake.dfs.fabric.microsoft.com/{src_lh['id']}/Tables"
    tables = sorted(e.name for e in mssparkutils.fs.ls(base) if e.name.startswith("stage_"))
    print(f"Copying {len(tables)} stage_* tables for tenant {tenant_id} from {source_workspace} -> this (prod) lakehouse\n")
    total = 0
    for t in tables:
        try:
            df = spark.read.format("delta").load(f"{base}/{t}").where(f"tenant_id = '{tenant_id}'")
            n = df.count()
            if n == 0:
                print(f"  {t}: 0 rows for tenant {tenant_id} (skip)")
                continue
            if spark.catalog.tableExists(t):
                df.write.format("delta").mode("overwrite") \
                    .option("replaceWhere", f"tenant_id = '{tenant_id}'") \
                    .option("mergeSchema", "true").saveAsTable(t)
            else:
                df.write.format("delta").mode("overwrite") \
                    .option("overwriteSchema", "true").saveAsTable(t)
            total += n
            print(f"  {t}: {n} rows -> prod")
        except Exception as e:
            print(f"  SKIP {t}: {str(e)[:200]}")
    print(f"\nCopied {total} rows across {len(tables)} tables. Next: register tenant {tenant_id} in "
          f"prod Audit.Tenants, then Orchestrate_Build (run_dentally_ingest=False).")
''', False),

    # 3 -- purge: delete this tenant from local (dev) stage --------------------
    (r'''def do_purge():
    if not confirm_purge:
        raise SystemExit("purge is destructive -- set confirm_purge=True to proceed.")
    tables = sorted(t.name for t in spark.catalog.listTables() if t.name.startswith("stage_"))
    print(f"Purging tenant {tenant_id} from {len(tables)} local stage_* tables\n")
    for t in tables:
        try:
            spark.sql(f"DELETE FROM {t} WHERE tenant_id = '{tenant_id}'")
            print(f"  purged tenant {tenant_id} from {t}")
        except Exception as e:
            print(f"  SKIP {t}: {str(e)[:200]}")
    print(f"\nStage purged. Also clear the warehouse: EXEC Audit.usp_Delete_All_Tenant @Tenant_ID={tenant_id} "
          f"and remove the row from Audit.Tenants (dev).")
''', False),

    # 4 -- dispatch ------------------------------------------------------------
    (r'''if mode == "copy":
    do_copy()
elif mode == "purge":
    do_purge()
else:
    raise SystemExit(f"unknown mode {mode!r} -- use 'copy' or 'purge'")
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
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Promote_Tenant_Stage.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, indent=1)
        f.write("\n")
    return out


if __name__ == "__main__":
    print("Wrote", build())
