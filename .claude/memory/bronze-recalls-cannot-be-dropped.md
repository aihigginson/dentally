---
name: bronze-recalls-cannot-be-dropped
description: Bronze.Recalls.Table.sql opens with DROP TABLE and cannot be rebuilt from Stage — deploying it emptied 45,241 rows on DEV.
metadata:
  type: project
---

**Never deploy `Fabric/Bronze.Recalls.Table.sql`.** It opens with `DROP TABLE IF EXISTS`, and
unlike every other Bronze table it cannot be reloaded afterwards:

* `Stage.Recalls` is a view over the lakehouse holding the **latest ingest batch only** — 292
  rows against 45,241 in Bronze.
* The loader's dedupe keeps one cycle per patient per type, so history never comes back.
* **The demo tenants are seeded straight into Bronze and never appear in Stage at all**
  (`usp_Load_Recalls` says so in its own comment), so a drop destroys tenants 11 and 12
  outright.

Done on DEV on 2026-10-26 while adding the `Reminders` column: 45,241 rows gone in a second.
Recovered only because `Silver.Recalls` mirrors Bronze 1:1 via MERGE and was not dropped —
rebuilt Bronze from Silver, restoring the exact per-tenant counts (11: 17,204, 12: 18,723,
100: 9,314). `Silver.Recalls._Raw_Json` is NULL on all rows, so it was no help.

**The second trap:** `Silver.usp_Load_Recalls` DELETEs Silver rows not present in Bronze. With
Bronze empty, running it would have wiped the only surviving copy. Do not run it to "fix"
an empty Bronze.

**Why:** Bronze is normally the throwaway layer, so dropping it reads as safe. For recalls the
layer below it is the backup, not the source.

**How to apply:** add a column with `ALTER TABLE Bronze.Recalls ADD <col> <type> NULL` in the
manifest — proven on DEV to preserve rows (Fabric supports ADD; it is ALTER COLUMN it
refuses). Keep the `.Table.sql` updated as the declared shape for `Check_Schema_Drift`, which
is all it is for; it now carries a warning banner. Other Bronze tables (Appointments,
Patients, Xero_*) genuinely are re-ingestable and have been deployed before — this one is the
exception. Related: [[never-deploy-an-input-table-in-a-release]],
[[demo-tenant-bronze-accumulates-every-generation]],
[[read-the-schema-before-querying-it]].
