"""
build_Freeze_Onboarding_Stage.py -- generator for Freeze_Onboarding_Stage.ipynb (Fabric).
Edit THIS, run `python build_Freeze_Onboarding_Stage.py` to regenerate the notebook.
Never hand-edit the .ipynb JSON (corrupts it); source is a list-of-lines.

Purpose: the onboarding SAFETY NET. `stage_*` is overwrite-per-tenant, so the first DELTA
run (updated_after) would replace a tenant's full onboarding stage with just the delta rows.
This notebook FREEZES a tenant's validated stage into immutable `init_stage_*` tables (same
LH_Dentally lakehouse, `init_` prefix) so deltas can then overwrite `stage_*` safely -- and a
tenant can be rebuilt from `init_stage_*` without re-pulling the API. Two directions:
  freeze  :  stage_*        -> init_stage_*   (run ONCE after onboarding validates)
  restore :  init_stage_*   -> stage_*        (rare; before a from-frozen rebuild)
Per-tenant (replaceWhere) so multiple practices coexist in the frozen tables.
"""
import json
import os

CELLS = [
    # 0 -- parameters ----------------------------------------------------------
    (r'''# Parameters -- Fabric overrides at runtime.
tenant_id   = "100"        # the practice to freeze/restore
direction   = "freeze"     # "freeze" (stage_* -> init_stage_*) or "restore" (init_stage_* -> stage_*)
init_prefix = "init_"      # frozen tables live as init_stage_<entity> in the SAME lakehouse
''', True),

    # 1 -- copy loop -----------------------------------------------------------
    (r'''tid = str(tenant_id)
where = "tenant_id = '" + tid + "'"

def copy_one(src_tbl, dst_tbl):
    df = spark.table(src_tbl).where(where)
    n = df.count()
    if n == 0:
        print("  skip " + src_tbl + " (0 rows for tenant " + tid + ")")
        return 0
    w = df.write.format("delta")
    if spark.catalog.tableExists(dst_tbl):
        w = w.mode("overwrite").option("replaceWhere", where).option("mergeSchema", "true")
    else:
        w = w.mode("overwrite").option("overwriteSchema", "true")
    w.saveAsTable(dst_tbl)
    print("  " + src_tbl + " -> " + dst_tbl + "  (" + str(n) + " rows)")
    return n

all_tables = [t.name for t in spark.catalog.listTables()]

if direction == "freeze":
    # every stage_* table (NOT the init_stage_* ones) -> init_stage_*
    srcs = [t for t in all_tables if t.startswith("stage_") and not t.startswith(init_prefix)]
    print("FREEZE tenant " + tid + ": " + str(len(srcs)) + " stage tables -> " + init_prefix + "stage_*")
    total = sum(copy_one(t, init_prefix + t) for t in srcs)
    print("Frozen " + str(total) + " rows. init_stage_* is now the onboarding snapshot; deltas may overwrite stage_* safely.")
elif direction == "restore":
    # every init_stage_* table -> the matching stage_* (strip the init_ prefix)
    srcs = [t for t in all_tables if t.startswith(init_prefix + "stage_")]
    print("RESTORE tenant " + tid + ": " + str(len(srcs)) + " frozen tables -> stage_*")
    total = sum(copy_one(t, t[len(init_prefix):]) for t in srcs)
    print("Restored " + str(total) + " rows into stage_*. Now rebuild Bronze->Gold (build-only).")
else:
    raise SystemExit("direction must be 'freeze' or 'restore', got: " + repr(direction))
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
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Freeze_Onboarding_Stage.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, indent=1); f.write("\n")
    return out


if __name__ == "__main__":
    print("Wrote", build())
