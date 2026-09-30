# Fabric notebook source -- REFERENCE COPY, NOT THE CANONICAL ARTEFACT.
#
# Fabric is canonical for notebooks. This file is the 'notebook-content.py' git-source
# format the Fabric REST API takes, NOT the .ipynb convention its siblings follow, because
# Maintain_Lakehouse was created and is updated through the API rather than by a build_*.py
# generator. Edit it in Fabric (or push with the API) and refresh this copy; do not expect
# 'python build_...' to regenerate it.
#
# Lives in BOTH workspaces, each bound to its own lakehouse, on a weekly schedule:
#     DEV   3156d67e-dc45-413b-9ff8-38f4eba022e1   Sunday 03:00 UTC
#     PROD  f8a98d96-bb4e-42ea-a92b-8adfbfcf7157   Sunday 04:00 UTC   (staggered: one F4)
#
# The GUIDs below are DEV's.

# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "e6cc2011-bd96-4164-8f21-ceb340e25449",
# META       "default_lakehouse_name": "LH_Dentally",
# META       "default_lakehouse_workspace_id": "22e235e2-7a32-4451-b573-8d5eb8532a23",
# META       "known_lakehouses": [
# META         {
# META           "id": "e6cc2011-bd96-4164-8f21-ceb340e25449"
# META         }
# META       ]
# META     }
# META   }
# META }

# CELL ********************

# =============================================================================
# Maintain_Lakehouse  --  compact and vacuum every Delta table
# =============================================================================
# ==> THE LAKEHOUSE HELD 41,826 FILES FOR 2.2 GB ACROSS THE TWO ENVIRONMENTS. <==
#
# Measured 2026-09-30 by listing OneLake directly:
#
#     PROD   22,486 files    798.7 MB   avg  36.4 KB   ~851 files per stage table
#     DEV    19,340 files  1,442.5 MB   avg  76.4 KB   ~741 files per stage table
#
# The file count is the SAME for every stage table regardless of size -- 851 files for a 2.3 MB
# table and 851 for a 21 MB one. That is not partitioning; it is one small file per ingest run,
# accumulating since the beginning and never compacted.
#
# It matters because OneLake bills TRANSACTIONS, not bytes. The Capacity Metrics app showed the
# lakehouse at ~560,000 CU-seconds across both environments for about 170 seconds of duration --
# roughly 1,700 CU per second, where the warehouse runs at ~3.7. That ratio is per-object
# overhead, not compute.
#
# ==> VACUUM KEEPS THE DEFAULT 168-HOUR RETENTION ON PURPOSE. <== Going shorter needs
# spark.databricks.delta.retentionDurationCheck.enabled = false, which disables the guard that
# stops vacuum deleting files a concurrent reader still needs. These accumulated over hundreds of
# runs, so a seven-day floor removes nearly all of them anyway. Nothing here is worth switching
# off a safety check for. Time travel beyond the window is lost, which is the point: these are
# staging tables, rewritten by the next ingest.
#
# ==> IT WRITES ITS OWN LOG TO Files/maint_log.txt. <== A notebook's stdout is not readable
# through the Fabric REST API, so the first version of this failed with nothing but "statement
# execution failures" to go on. Everything below is caught and written to OneLake, where it can
# be read back without opening the workspace.
# =============================================================================

import traceback
from datetime import datetime, timezone

LOG = []


def say(msg):
    print(msg)
    LOG.append(f"{datetime.now(timezone.utc):%H:%M:%S}  {msg}")


started = datetime.now(timezone.utc)
say(f"Maintain_Lakehouse starting {started:%Y-%m-%d %H:%M:%S} UTC")

# ---- discover the tables ----------------------------------------------------
# Every step is guarded: the first version put discovery outside the try, so one awkward schema
# took the whole cell down and left no clue which.
targets = []
try:
    schemas = []
    try:
        # ==> SHOW SCHEMAS RETURNS THE FULLY-QUALIFIED NAME. <== On a schemas-enabled lakehouse it
        # comes back as 'DEV - DM Dentally.LH_Dentally.dbo', and passing that straight to
        # SHOW TABLES IN produces `default.DEV - DM Dentally.LH_Dentally.DEV - ...` and
        # SCHEMA_NOT_FOUND. Only the last segment is the schema.
        raw = [r[0] for r in spark.sql("SHOW SCHEMAS").collect()]
        say(f"schemas seen: {raw}")
        schemas = sorted({s.split(".")[-1] for s in raw})
        say(f"schemas used: {schemas}")
    except Exception as e:
        say(f"SHOW SCHEMAS failed ({str(e)[:90]}) -- falling back to dbo")

    if not schemas:
        schemas = ["dbo"]

    for sch in schemas:
        if sch.lower() in ("information_schema", "sys", "queryinsights"):
            say(f"skipping system schema {sch}")
            continue
        try:
            rows = spark.sql(f"SHOW TABLES IN `{sch}`").collect()
            for r in rows:
                targets.append((sch, r["tableName"]))
            say(f"{sch}: {len(rows)} table(s)")
        except Exception as e:
            say(f"SHOW TABLES IN {sch} failed: {str(e)[:110]}")
except Exception:
    say("discovery failed outright:\n" + traceback.format_exc()[:1500])

say(f"{len(targets)} table(s) to maintain")

# ---- compact and vacuum -----------------------------------------------------
ok, failed = 0, []
for sch, tbl in targets:
    name = f"`{sch}`.`{tbl}`"
    try:
        spark.sql(f"OPTIMIZE {name}")
        spark.sql(f"VACUUM {name} RETAIN 168 HOURS")
        ok += 1
        say(f"  ok  {sch}.{tbl}")
    except Exception as e:
        failed.append(f"{sch}.{tbl}")
        say(f"  SKIP {sch}.{tbl}: {str(e)[:130]}")

took = (datetime.now(timezone.utc) - started).total_seconds()
say(f"maintained {ok} of {len(targets)} table(s) in {took:.0f}s; {len(failed)} skipped")

# ---- leave the evidence where it can be read --------------------------------
try:
    import notebookutils
    notebookutils.fs.put("Files/maint_log.txt", "\n".join(LOG), True)
    print("log written to Files/maint_log.txt")
except Exception:
    try:
        mssparkutils.fs.put("Files/maint_log.txt", "\n".join(LOG), True)
        print("log written to Files/maint_log.txt (mssparkutils)")
    except Exception:
        print("could not write the log file:\n" + traceback.format_exc()[:800])

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
