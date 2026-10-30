---
name: targets-rework-handover-30-oct
description: "WHERE THE TARGETS REWORK STOPPED on 2026-10-30 — what is deployed to DEV, what is committed but NOT deployed, the ordered deploy sequence, and what is waiting on the owner in the model."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-30T00:44:17.965Z
---

Stopped late on 2026-10-30. 25 commits, all pushed. Delete this note once the open items below
are closed — it is a handover, not a standing fact.

## Deployed to DEV and verified

- **The target grid is keyed on the drop-down text.** `[Selection]`, `[Role]`, no level/key/tenant
  addressing. See [[targets-are-keyed-on-the-dropdown-text]] for the four silent failure modes.
- **`Gold.Aggregate_Period_Targets` builds from `Fact_Node_Targets`**; `Fact_Daily_Targets` is out
  of the DAG. Proven equal to the explosion it replaced: 0 only-in-old, 0 only-in-new, 0 values
  differing. 2,434 rows where there were 263,874.
- **`Gold.Dim_Hierarchy_Node`** — selection → the sites it covers; the one table carrying `Level`
  and `Node_Key`.
- **The `MIN(Tenant_ID)` access stamp** so the blanket RLS rule covers both target tables
  unchanged. 0 cross-client rows visible when real `vw_User_Tenant_Access` sets are simulated.
- **Top Node** end to end: AppDB → `Input_Stage` → `Meta.usp_Sync_Access_From_AppDB` →
  `Security.Application_Users`, plus the subscriptions picker and `/api/filters` subtree.
- **The app pushes `[Selection]` AND `[Client ID]`** at the targets table. The Client ID half was
  missing at first and Skeleton Group's "North" showed Demonstration Practice's targets — both
  clients have a North, a South, a London and a Manchester.
- **The measure sweep**: 36 `[Target Level]` → `[Role]`, 44 `"Practice"` → `"All Roles"`.

## Committed but NOT deployed — do this first

`fk_Site` → `fk_Practice_Site` on the three `Aggregate_Site_*` tables (90 refs, 11 files).
**Needs an ordered run, not a drive-by:**

1. the three `Table.sql` (DROP/CREATE — they come back EMPTY)
2. the three loaders **and** `usp_Load_Fact_Metric_Actuals`, which reads `a.fk_Site` from them
3. run the three aggregates, **then** `Fact_Metric_Actuals`
4. `EXEC Meta.usp_Create_Gold_Views` — **not optional**, a PBI view pins its columns at CREATE
   time ([[a-vw-override-silently-drops-new-columns]])
5. owner re-reads and relinks in the model

`Audit.RI_Check_Config` has three RI rows on that column; they are renamed in the file but the
check will fail until step 1 lands.

## Waiting on the owner, in the model

The owner maintains RLS rules and model presentation by hand — the csx no longer touches either.

- RLS rule on `_Node Targets`; `Scripts/Find_Broken_RLS.csx` names anything missing one.
- **Hide `[Tenant ID]`** on `_Node Targets` and `Aggregate Period Targets`. On the Skeleton Group
  row it reads `21`; grouping by it credits Skeleton Alpha with the whole group.
- Drop `_Daily Targets` from the model — then the view, table and loader can go.
- Do **not** import `List Hierarchy Node` yet: nothing in the model reads it, and a second path to
  `List Practice Sites` is what broke Home last time.
- Autodetect relationships OFF (owner's own note).

## Open, not started

- **Five KPIs ignore every filter** — Open Courses Value / Open Courses / Open (No Appt) read
  `_Treatment Plans`, which DOES expose `fk Practice Site`, so they need **one relationship**.
  Email/Phone Details Rate aggregate off `List Patients`, a dimension, and `Dim_Patients` carries
  only the varchar business key. Owner's fix, agreed: add `Has_Email` / `Has_Phone` to
  `Gold.Aggregate_Site_Patient_Current` — it is already one row per patient, already resolves
  `pk_Practice_Site`, and already carries `Active_Patients` from the same `dp.Active` the measures
  use, so the denominator is definitionally identical. Mirror `NOT ISBLANK(...)` exactly rather
  than reusing `Is_Email_Missing`, and verify the PER-CLIENT rate — the 96.1% / 97.3% on screen
  are the bleeding figures, so matching them proves nothing. Fold into the same run as the rename,
  which drops that table anyway. `Scripts/Find_Unfiltered_Facts.csx` lists the rest.
- **A single-site practice appears twice** (Practice and Site), same actuals, different targets —
  a quantity rolls up, never down, so the site inherits nothing. Owner to choose: suppress a Site
  node whose site set equals its parent's, or roll a quantity down to a sole child.
- The targets POST still writes the old `Level_Type`/`Level_Key` shape — **fix before entering any
  real targets for Skeleton Group.**
- Targets admin UI (page per level, greyed on `Is_Entered`); `Plan_Capitation_Rate.Plan_Name`;
  the unconstrained Practice Sites alias; collapsing the four target builders into one.

## Watch

Nightly build 22:03 runs the rewired DAG (`GOLD_FACT_NODE_TARGETS` → `GOLD_AGG_PERIOD_TARGETS`)
for the first time — check `Audit.Process_Execution_Log` before trusting the board.

Uncommitted in the tree and NOT mine: seven `PBI/My_Data.Report` visual.json files and an
untracked `Sales Leads/`. Both predate this session.
