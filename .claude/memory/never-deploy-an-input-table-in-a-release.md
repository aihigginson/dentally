---
name: never-deploy-an-input-table-in-a-release
description: "Fabric/Input.*.Table.sql files start with DROP TABLE, and Input.* is owner-curated data - deploying one empties it."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T10:02:59.526Z
---

`Fabric/Input.*.Table.sql` files begin `DROP TABLE IF EXISTS` followed by `CREATE TABLE`, and
the `Input` schema holds **owner-curated data** synced from AppDB, not code. Putting one in a
release manifest silently empties it.

**Why:** on 2026-09-27 I added `DEPLOY Fabric\Input.Plan_Capitation_Rate.Table.sql` to V189
purely to pick up a one-line comment fix. It wiped the per-plan monthly fees, so no plan
resolved, no member had a spell, and `usp_Load_Fact_Revenue` produced **zero** capitation rows
while reporting success. It surfaced as the reconciliation guard reporting that all 120,553
patient-months had changed — which read like a logic bug, not a data wipe.

**How to apply:** never deploy an `Input.*` table unless the intent really is to rebuild it
empty. To fix a comment in one, change the repo file and let it apply the next time the table
is legitimately rebuilt. If it happens: `Input_Stage` is populated by a separate Fabric
pipeline and survives, so
`DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Meta.usp_Sync_Input_From_AppDB @Mode='PROD',
@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;` reloads it. Add a pre-flight
guard asserting the input is non-empty before any loader that depends on it, so the failure
lands at the front of the release rather than as a silent zero four steps later. Related:
[[never-compare-two-rolling-windows-built-on-different-days]].
