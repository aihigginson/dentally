# Overnight Build — Fabric Data Pipeline spec

Purpose: a nightly, end-to-end refresh so the warehouse and the Power BI dataset never go
stale (the disabled prod build is what stranded `Open Courses Value` — the KPI snapshot spine
and `Dim_Date` stop advancing when nothing runs `usp_Load_All`).

This is a **build spec** — you create the Fabric Data Pipeline + schedule in the portal; the
SQL orchestrators it calls already exist in the warehouse.

---

## 1. What the build does (stages, in order)

```
[1] Source ingest    Dentally API  ->  Stage (OneLake Delta)     per tenant
[2] Bronze load      Stage         ->  Bronze                    per tenant   Audit.usp_Load_Bronze
[3] Silver + Gold    Bronze        ->  Silver -> Gold            all tenants  Audit.usp_Load_All
[4] Model refresh    Gold (warehouse) -> Power BI semantic model (dataset)
```

Each stage runs only if the previous succeeded (Fabric "on success" dependency).

**Demo vs real data (important):** today prod tenant 11 (and dev T11–T14) are loaded into
**Stage** by the Python seeders (`API/seed_onelake_prod.py` / `API/seed_onelake.py`), run
out-of-band — there is **no live Dentally API extract** yet. So until the real API extract is
wired, **Stage stage [1] is a placeholder** and the nightly job effectively runs [2]→[3]→[4]
against the already-seeded Stage. Keep activity [1] in the pipeline but disabled/empty for now;
swap in the Dentally extract pipeline when real data goes live. [2]→[4] still keep the snapshot
spine + `Dim_Date` current every night, which is the actual fix for the stale-KPI problem.

---

## 2. Activities (Fabric Data Pipeline)

### Activity 1 — (placeholder) Source ingest  *(disabled until real API extract exists)*
- Type: **Invoke pipeline** → the Dentally API→Stage ingest pipeline (the per-entity Bronze
  ingest pipelines), or a notebook.
- For the demo: leave disabled. Stage is seeded manually.

### Activity 2 — Bronze load (per tenant)
Bronze is **per-tenant** (`Audit.usp_Load_Bronze @Tenant_ID, @Full_Refresh`). Drive it with a
tenant loop so it's data-driven, not hardcoded:

- **Lookup** `Get-Tenants` (against the warehouse, prod connection):
  ```sql
  SELECT Tenant_ID FROM Audit.Tenants WHERE Is_Active = 1 ORDER BY Tenant_ID;
  ```
  (If `Audit.Tenants` has no `Is_Active`, just `SELECT Tenant_ID FROM Audit.Tenants`.)
- **ForEach** `For-Each-Tenant` over `@activity('Get-Tenants').output.value`
  (Sequential = ON — Stage uses `replaceWhere`, keep tenant loads serialized to avoid contention):
  - **Script** activity `Load-Bronze-Tenant` (warehouse connection):
    ```sql
    DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
    EXEC Audit.usp_Load_Bronze
         @Tenant_ID    = @{item().Tenant_ID},
         @Full_Refresh = 0,
         @Run_Inserts  = @i OUT,
         @Run_Updates  = @u OUT,
         @Run_Deletes  = @d OUT;
    ```
  `@Full_Refresh = 0` = incremental (the nightly default; full-refresh plumbing exists but the
  Stage_Ingest full-reload path is not wired — leave at 0).

### Activity 3 — Silver + Gold (all tenants, one call)
- **Script** activity `Load-Silver-Gold` (warehouse connection), depends on `For-Each-Tenant` success:
  ```sql
  EXEC Audit.usp_Load_All @Mode = 'PROD';
  ```
  This already chains, in dependency order: all Silver loads → Gold dims (incl. **`Dim_Date`**,
  `Dim_Date_Grouping`) → Gold facts → **`Fact_KPI_Snapshot`** (advances the weekly/MTD spine to
  "today") → aggregates. `@Mode='PROD'` = live (not the TEST path).
- Set the activity **timeout** generously (e.g. 1–2h) and **retry = 1**.

### Activity 4 — Semantic model refresh  (the step that actually updates the report)
Depends on `Load-Silver-Gold` **success**. Without this, the warehouse is fresh but the report
is not — this is exactly what stranded `Open Courses Value` (warehouse advanced, dataset stale).

**Preferred — native "Semantic model refresh" activity** (Fabric Data Pipeline):
- Activity type: **Semantic model refresh**.
- Connection: the workspace holding **DM Dentally** (prod workspace for the prod pipeline).
- Semantic model: **DM Dentally**.
- **Wait on completion = ON** — the refresh is **asynchronous**; if the activity returns before
  the refresh finishes, the pipeline will falsely report success. The native activity polls for
  you when this is on.
- Commit/refresh type: full.

**Fallback — Web activity → Power BI REST enhanced refresh** (if the native activity isn't available
on your capacity):
1. **Web** activity `Start-Refresh`:
   - `POST https://api.powerbi.com/v1.0/myorg/groups/{workspaceId}/datasets/{datasetId}/refreshes`
   - Body: `{ "type": "full", "notifyOption": "NoNotification" }`
   - Auth: the pipeline identity / a service principal with **Dataset.ReadWrite.All** and
     **Build** on the model (resource `https://analysis.windows.net/powerbi/api`).
2. **Until** loop `Wait-Refresh` — poll
   `GET …/datasets/{datasetId}/refreshes?$top=1` every ~60s until
   `status` ≠ `Unknown` (i.e. `Completed`/`Failed`); fail the pipeline on `Failed`.

**Prereqs / gotchas:**
- The run identity (prod = **ops@**, dev = **dev@**, or a dedicated SP) must have **refresh
  rights** on the model and be able to reach the data source. (Prod's model refresh is already
  bound to the app SP ea34f12f — ACCESS_MODEL.md §4b — so reuse that identity if refreshing via SP.)
- Tenant setting **"Allow XMLA endpoint / dataset refresh via API"** / service-principal API access
  must be enabled for the SP path.
- Keep refresh **after** `Load-Silver-Gold`, never in parallel — otherwise it reads half-built Gold.

---

## 3. Schedule
- **02:00 Europe/London**, daily. (After midnight so `TODAY()`-based snapshot rows are the new day.)
- One schedule per environment (separate dev + prod pipelines).

## 4. Identity (per ACCESS_MODEL.md)
- **prod** pipeline runs as **ops@analytically.info** (Admin on prod workspace).
- **dev** pipeline runs as **dev@analytically.info**.
- Warehouse connections use the same identity; the semantic-model refresh needs that identity to
  have refresh rights on the dataset (already true for the SP-based refresh binding — see
  ACCESS_MODEL.md §4b).

## 5. Failure handling & rerun
- Every step logs to the **Audit ETL run log** via `ETL_Start_Run` / `ETL_Run_Process`
  (parent/child UUIDs), so a failed entity is visible in `Audit` without pipeline logs.
- On pipeline failure: add a **Teams/email alert** activity (or Fabric Activator) on the
  failure path.
- To re-run only what failed (not the whole build) use the existing
  `Audit.usp_Rerun_Failed_Jobs` (dependency-aware; reseeds failed Process_Config codes and
  chains downstream). Wire a manual "rerun failed" pipeline that calls it, or run it ad hoc.

## 6. Idempotency / safety
- [2] and [3] are **incremental upserts** (watermark / hash-gated), safe to re-run.
- No reseed, no DROP/CREATE — the nightly build never changes schema (schema changes ride the
  `Releases/Vnnn` manifests via the Deploy Warehouse action, kept OUT of this pipeline).
- Keep the **warehouse out of the Fabric *deployment* pipeline** (that only syncs schema). This
  build pipeline only *runs* loads + refresh; it does not promote code.

## 7. Per-environment parameters
| Param | dev | prod |
|-------|-----|------|
| Warehouse server | `…-4i26…` (WH_Dentally) | `…-eljz…` (WH_Dentally) |
| Tenants | from `Audit.Tenants` (T11–T14) | from `Audit.Tenants` (T11 demo) |
| Semantic model | dev DM Dentally | prod DM Dentally |
| Run identity | dev@ | ops@ |

---

## 8. Immediate one-off (fixes today's stale prod KPI)
Before the schedule exists, run the Silver/Gold stage once on prod to un-stick `Open Courses Value`:
```sql
EXEC Audit.usp_Load_All @Mode = 'PROD';
```
then refresh the prod dataset. (This is exactly Activity 3 + Activity 4 run by hand.)
