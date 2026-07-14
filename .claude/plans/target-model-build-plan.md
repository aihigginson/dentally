# Target Model — Development / Build Plan

Status: **PLAN — 2026-07-14. Not started.** Implements the agreed design in
`target-model-redesign.md` (do not relitigate design decisions here — this is the *how*).
Backend = **Fabric SQL Database** (option A from the 2026-07-14 discussion). Deferred until prod is stable.

---

## 0. Architecture at a glance

```
  [Settings screens]  --write/read (ms)-->  [Fabric SQL Database]   <- source of truth for the 3 Input tables
   Web/index.html                              Input.Practitioner_Role
   Web/app.py (_appdb_conn)                    Input.Targets  (reshaped)
                                               Input.Metric_Variance
                                                   |  (auto-mirror to OneLake, ~seconds)
                                                   v
  [Orchestrate_Build]  --nightly copy-->   [WH_Dentally]  Dim_Practitioner.Custom_Role = COALESCE(override, Dentally)
                                                          Fact_Targets / _Daily / _Effective  (rebuilt from new shape)
                                                   |
                                                   v
  [DM Dentally model]  reads the derived target FACTS (as today) + Custom_Role-driven measures
```

Two consumers of the Input data: (1) the **screens** (transactional CRUD — the SQL DB, instant); (2) the
**warehouse** target-fact loads (analytical — nightly). The model reads the derived facts, **not** the raw
Input tables, so only the warehouse needs a read path back from the SQL DB.

### PHASE 0 — PROVEN 2026-07-14. Both pipes work.
- **AppDB** SQL Database created in the DEV workspace (item id `4c31e989-45ca-456c-a319-1a7a262c8aa3`;
  server `emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.database.fabric.microsoft.com`,
  catalog `AppDB-4c31e989-...`). Schema applied via `AppDB/AppDB_Input_Schema.sql`.
- **Pipe 1 (app -> AppDB):** SPIKE PASS via `AppDB/Provision_And_Test.ps1` — connect + schema + CRUD. The deploy
  SP connects with NO manual DB grant (workspace-admin role maps through). App will use the Container App
  managed identity (Phase 4), granted the same `CREATE USER ... FROM EXTERNAL PROVIDER` way (datareader/writer).
- **Pipe 2 (AppDB -> WH_Dentally):** FULL PIPE PASS. WH_Dentally **cross-database queries** AppDB by DISPLAY NAME:
  `SELECT ... FROM [AppDB].[Input].[Targets]` resolves and returns data; a marker row mirrored across in ~seconds.
- **So option B is TRIVIAL T-SQL — no Data-pipeline Copy activity, no notebook cell.** The copy step is just a
  warehouse SP doing `MERGE INTO Input.<t> USING (SELECT * FROM [AppDB].[Input].<t>) ...` (or TRUNCATE+INSERT for
  3 tiny tables), added early in Orchestrate_Build. Option A (shortcut) not needed.

---

## 1. Schema + migration

**Fabric SQL DB (dev + prod), schema `Input`:**
- `Practitioner_Role (Tenant_ID int, Practitioner_ID <id>, Custom_Role varchar(100), Updated_At datetime2)` — PK (Tenant, Practitioner). One row per practitioner (SCD-1).
- `Targets (Tenant_ID int, FY smallint, Metric varchar(100), Target_Level varchar(100), Target_Value decimal(18,4), Updated_At)` — PK (Tenant, FY, Metric, Target_Level). Target_Level ∈ {'Practice'} ∪ Custom_Roles. Sparse.
- `Metric_Variance (Tenant_ID int, Metric varchar(100), Variance decimal(9,4), Updated_At)` — PK (Tenant, Metric). Per-metric, not per-FY/cell.

**Migration of existing warehouse targets** (one-off script):
- Old `Input.Targets` (Tenant/Site/Practitioner/Metric/Period_Type/Period_Value/Target_Value/Variance) → new shape:
  - `Period_Type='all_time'`, Site/Practitioner NULL rows → `Target_Level='Practice'`, FY = current.
  - **Per-practitioner target rows are DROPPED** (design: judge vs role). Flag any before dropping so the owner re-sets at role level.
  - `Variance` → `Input.Metric_Variance` (one per metric; if they differ across rows, take the Practice-level one).
- Seed `Practitioner_Role` from the current Dentally role (defaults) so nothing is blank on day one.

**`Config.Metric_Definitions`** (stays in the warehouse): add `Aggregation_Class` (sum|ratio|snapshot|min, backfill
from Target_Type) + `Splits_By_Role` bit (backfill from Supports_Practitioner). Keep Range_Type + Format. These
collapse Supports_Site/Supports_Practitioner + the measure-shape zoo.

## 2. Warehouse consumption (the biggest SQL change)

- **Orchestrate_Build:** add the Input copy step (§0 option B), ordered before the dims/target facts.
- **`Dim_Practitioner`:** add `Custom_Role` column; load = `COALESCE(Input.Practitioner_Role.Custom_Role, <Dentally role>)`. Survives the nightly rebuild because the override lives in the SQL DB, not the dim.
- **Target facts** (`Fact_Targets` / `Fact_Daily_Targets` / `Fact_Effective_Targets`): rebuild from the new
  `Input.Targets` shape keyed on (FY, Metric, Target_Level) and grouped by `Custom_Role`. This is the core rewrite —
  the level dimension is now Practice+Role, not Site/Practitioner.
- Process_Config/Dependency: register the copy step; re-point target-fact deps. Regenerate the dep graph.
- CI: the dependency-completeness guard (`Check_Process_Dependencies.ps1`) should still pass.

## 3. Measures (Tabular Editor)

- **Aggregation** grouped by `Custom_Role`; ~4 templates by `Aggregation_Class` (sum/ratio/snapshot/min) replacing
  the cur/currate/snap/rate/cum zoo.
- **Target resolution by filter:** practitioner selected → their Custom_Role column; role → that column; All →
  Practice column; practice-grain metric (`Splits_By_Role=0`) → always Practice, grey under role/practitioner;
  blank cell → uncoloured.
- **Role filter** switches from Dentally roles → `Custom_Role`.
- RAG uses the per-metric `Metric_Variance` band, Range_Type-aware (above/below one-sided, within symmetric).

## 4. App backend (`Web/app.py`)

- Add `_appdb_conn()` alongside `_fabric_conn()` — same token pattern, pointed at the Fabric SQL DB endpoint
  (env-per-env: `APPDB_SERVER`/`APPDB_DB`). Auth via the existing app SP / Container App managed identity
  (mirror the Xero-token managed-identity pattern).
- Endpoints (all gated on `Maintain_Targets`, reusing `_get_user_info`'s `maintain` flag; tenant-scoped writes):
  - `GET/POST /api/roles` — practitioners + their Custom_Role (drag screen). Writes `Input.Practitioner_Role`.
  - `GET/POST /api/target-grid` — metrics × (Practice+roles) grid; GET also returns the **current actual** per
    cell (for the actual-above-entry display, read from the warehouse `Fact_Metric_Actuals`) + the FY list +
    a copy-from-FY source. Writes `Input.Targets`.
  - `GET/POST /api/variances` — per-metric variance. Writes `Input.Metric_Variance`.
- Repoint the existing `/api/targets` + `/api/practitioner-pay` reads/writes from the warehouse to the SQL DB
  (or retire `/api/targets` in favour of `/api/target-grid`). Keep `Practitioner_Pay` in the same SQL DB.

## 5. App frontend (`Web/index.html`)

- New **Settings section** with a left sub-nav: **Practitioner Roles | Targets | Variances**. Gate on `maintain`.
- **Roles** = repurpose the existing defunct in-app targets screen into a drag board: columns = roles (Dentally
  defaults + custom), cards = practitioners, drag between, "Add role" button.
- **Targets grid** = rows metrics, cols Practice+roles (derived from Roles); **current actual shown ABOVE each
  entry cell**; FY selector; **Copy-from-SELECTED-FY** button (source-year picker, seeds a blank year); per-metric
  variance shown once per row.
- Wire to the new endpoints; optimistic save + toast; instant because it's the OLTP store, not the warehouse.

## 6. Cutover + retire

- Retire the spreadsheet: `Generate_Targets_Template` / `Load_Targets_From_Template`.
- Switch the Role filter to `Custom_Role` across the reports.
- Regression: targets-vs-actuals for existing Practice-level metrics must be unchanged pre/post migration.
- Deploy order: SQL DB schema → migration → warehouse (manifest, BOTH branches — prod action reads `dev`) →
  Orchestrate_Build → measures + refresh → app (dev auto-deploy, prod on main). Then delete spreadsheet path.

---

## Open decisions to confirm before building
1. **Read path** — option B (copy step) vs A (shortcut)? Recommend **B**.
2. **App→SQL DB auth** — Container App managed identity vs the app SP (client-credentials)? (Xero writes use managed
   identity → KV; reuse that identity for the SQL DB.)
3. **Migration** — confirm per-practitioner targets are dropped (design says yes); surface the dropped set to the
   owner so they re-enter at role level.
4. **One SQL DB per env** (dev + prod), consuming F2 CU (trivial for CRUD) — accept, or split capacity later.
