# Targets rework — backup, release order and rollback

Written 30 Oct 2026, against the state of AppDB-prod and the prod warehouse as measured that day.

---

## 1. What is actually at risk

**Not the actuals.** Everything in Bronze/Silver/Gold that came from Dentally can be rebuilt by
re-ingesting. It costs time and capacity, not information.

**The AppDB is the whole risk.** Every row in `Input.*` was typed by somebody and exists nowhere
else:

| Table | Prod rows | Why it is irreplaceable |
|---|---:|---|
| `Input.Targets` | **334** | Maple's own, hand-set over months. The seeder has never run against them. |
| `Input.Application_Users` | 66 | Who can sign in, and as what. Empty = nobody has access. |
| `Input.Metric_Variance` | 36 | The RAG bands that go with those targets. |
| `Input.Practitioner_Role` | 15 | Role per practitioner — drives every per-role measure. |
| `Input.Practitioner_Pay` | 10 | FTE and associate share. |
| `Input.Plan_Capitation_Rate` | 8 | From the plan provider's spreadsheets. |
| `Input.Roles` | 5 | The client's own vocabulary. |
| `Input.Practice_Config` | 1 | Financial year start month. |
| `Input.Billing_Contact` | 1 | Who gets the invoice. |
| `Input.Access_Log` | 67 | History only — losing it is an annoyance, not a problem. |

`Input.Client`, `Client_Tenant`, `Client_Region`, `Client_Area`, `Site_Area` are **empty on prod**.
See §3 — that is a blocker, not a backup concern.

---

## 2. Three layers, and what each is actually for

Take **all three**, in this order. They fail in different ways on purpose.

### a. Off-box file export — the one that survives anything

```
python AppDB/Backup_AppDB.py AppDB-prod
```

Writes `Backups/AppDB-prod_<UTC stamp>/` — one JSON per table plus `manifest.json` carrying a row
count and SHA-256 for each. It re-reads every file and re-hashes it before reporting success, so a
half-written file is found now rather than during a rollback. Decimals are stored as strings, so no
target can come back different in the last place.

`Backups/` is in `.gitignore` — it is customer data and must not reach the repo. OneDrive backs it up.

Restore from it:

```
python AppDB/Restore_AppDB.py Backups/AppDB-prod_<stamp> --list
python AppDB/Restore_AppDB.py Backups/AppDB-prod_<stamp> Targets --dry-run
python AppDB/Restore_AppDB.py Backups/AppDB-prod_<stamp> Targets
```

It verifies the manifest hash before reading, refuses if the table has lost a column the export has,
and commits DELETE+INSERT together so a table is never half of each generation.

### b. In-database snapshot — the fast one

```
AppDB.Backup_Input_Snapshot.sql        -- prints a stamp, e.g. 20261030_1530. KEEP IT.
```

Copies every `Input.*` table to `Backup.<table>__<stamp>`. Instant to take, instant to restore from,
and it dies with the database — which is the mistake it is most likely to be needed for. That is why
the files come first.

Roll back with `AppDB.Rollback_Input_Snapshot.sql` after setting **both** parameters at the top:

```sql
DECLARE @stamp  VARCHAR(20)    = '20261030_1530';   -- required, it will not guess
DECLARE @tables NVARCHAR(2000) = 'Targets';         -- or 'ALL', or 'Targets,Roles'
```

It restores rows, not schema. If a migration dropped or retyped a column the snapshot holds, it
refuses and tells you to reverse the DDL or use (c).

### c. Azure point-in-time restore — the whole-database net

AppDB-prod is Azure SQL **Basic** with PITR reaching back **7 days** (measured: earliest restore
23 Oct 2026). It restores the entire database, schema included, to **a new database name** which
then has to be swapped in. Right tool for "the migration corrupted everything"; wrong tool for "put
Maple's targets back".

```
az sql db restore --dest-name AppDB-prod-rollback --name AppDB-prod \
   --server sql-analytically --resource-group rg-analytically --time <ISO timestamp>
```

> **This is the real reason not to rush.** The 7-day window is the outer limit of "we can undo this".
> Do not start the release on a day you will not be able to look at it for a week.

### Both paths are proven, not assumed

Tested on AppDB-dev, 30 Oct: `Input.Roles` emptied deliberately, restored to 4 rows from the file
export; emptied again, restored to 4 rows from the in-database snapshot. The rollback also correctly
refused to touch anything `@tables` did not name.

---

## 3. What running this against prod actually found

Two things, both of the same kind: **state that only ever existed on dev**.

### a. The hierarchy was empty (fixed, step 1 below)

`Input.Client`, `Client_Tenant`, `Client_Region`, `Client_Area` and `Site_Area` held nothing on
prod. `Gold.usp_Load_Fact_Node_Targets` builds its tree from those, and `Client_Keying` backfills
`Client_ID` *from* `Client_Tenant` — so against an empty map every target keeps a NULL `Client_ID`
and the loader skips it. Maple's 334 targets would have been invisible on every report.

`AppDB/Seed_Hierarchy_Prod.sql` fills it: client 100 → tenant 100, one region, one area, Maple's
site (`027ed563-acef-4734-bdc9-40e4330347f3`) into it. The region and area names never appear —
Maple has one site, so the fold keeps only its Practice node. Client **100**, not 1000: 1000 is the
legal entity invoices are raised to; the tenant belongs to 100.

### b. Twenty-two columns that only existed on dev

Diffed, rather than discovered one failure at a time:

| | missing on prod |
|---|---|
| `Input.Targets` | `Level_Type`, `Level_Key`, `Client_ID` |
| `Input_Stage.Targets` | `Level_Type`, `Level_Key`, `Client_ID` |
| `Input_Stage.Application_Users` | `Top_Node_Level`, `Top_Node_Key` |
| six tables, both schemas | `Client_ID` |
| `Plan_Capitation_Rate`, both schemas | `Plan_Name` |

**Nothing in the repo ever created `Input.Targets.Level_Type` or `Level_Key`.** They reached
AppDB-dev by hand and were never written down, so `Target_Node_Key` — which builds computed columns
over them — would have failed on its second batch against prod. `Fabric/AppDB.Migration.Target_Level_Columns.sql`
now adds them.

And `Input_Stage.Targets.Table.sql` *does* declare them, but it is guarded by `IF OBJECT_ID IS NULL`
— so re-deploying it against an existing table is a silent no-op and the column never arrives.
`Migrations/V154__targets_rework_input_columns.sql` adds all 22 with guarded ALTERs; validated
against dev as a complete no-op.

> The ordering trap: `Web/appdb_sync.py` takes its column list from the **target** (`Input_Stage`),
> so a column AppDB has and staging does not is dropped in transit, silently. And the new
> `Meta.usp_Sync_Input_From_AppDB` names those columns in its INSERT lists, so deploying it before
> V154 makes every sync fail on an invalid column name.

---

## 4. Release order

Steps 0–9 are **done on prod** (30 Oct 2026); it is paused before **8b**, the only step that
touches what the live reports read. Everything up to the point of no return is additive —
inserts and nullable `ALTER ... ADD` — and prod reporting is untouched throughout: the old
`Fact_Daily_Targets` chain still feeds `Aggregate_Period_Targets`, and the live app reads the
hierarchy tables only from its admin screen.

| # | Step | Where | Gate | State |
|---|---|---|---|---|
| 0 | `Backup_AppDB.py AppDB-prod`, then `AppDB.Backup_Input_Snapshot.sql` | AppDB | manifest verified; snapshot counts match | **done** — files `20261030_143700Z`, snapshot `20261030_1447` |
| 1 | `AppDB/Seed_Hierarchy_Prod.sql` | AppDB | site → area → region → client resolves | **done** |
| 2 | `AppDB.Migration.Client_Keying.sql` | AppDB | 0 unmapped on every table | **done** — 334 targets on client 100 |
| 3 | `AppDB.Migration.Target_Level_Columns.sql` | AppDB | both columns present, nothing backfilled | **done** — all 334 rows still read as their own practice |
| 4 | `AppDB.Migration.Top_Node.sql` | AppDB | `Top_Node_Level`/`Key` on `Application_Users` | **done** — 66 users, all at the root |
| 5 | `AppDB.Migration.Target_Node_Key.sql` | AppDB | PK lists 6 key columns; rows = distinct addresses | **done** — 334 rows, 334 addresses |
| 6 | `Migrations/V154__targets_rework_input_columns.sql` | warehouse | all 22 report `present` | **done** — schema diff now reports **0 gaps** |
| 7 | **`AppDB.Migration.Roles_Are_Client_Wide.sql`** | AppDB | roles at `('Practice','100')`; `All Roles` still 106 | **done** — 228 role rows re-addressed, every count and sum byte-identical |
| — | `Migrations/V155__metric_rolls_up_and_top_node.sql` | warehouse | 20 up / 28 down, nothing NULL | **done** — `Rolls_Up` was missing; the node loader cannot run without it |
| 8a | **Additive**: `Dim_Hierarchy_Node`, `Fact_Node_Targets`, `usp_Load_Fact_Node_Targets`, `Meta.usp_Sync_Input_From_AppDB` | warehouse | objects exist; model untouched | **done** |
| 9 | AppDB sync, then `usp_Load_Fact_Node_Targets` | warehouse | `Dim_Hierarchy_Node` has Maple's one node | **done** — 1 node, 334 rows, all entered, sum 21,435,541 |
| — | Snapshot the old aggregate | warehouse | `Backup.Aggregate_Period_Targets__pre_8b` = 478 rows | **done** — makes 8b reversible |
| — | Merge `dev` → `main`, then `MAINTENANCE=1` on `ca-analytically-prod` | CI + Azure | `app.analytically.info` returns 503 "Down for maintenance"; `/health` still 200 | **done** |
| 8b | **The switch**: `Aggregate_Period_Targets` rev *03, its loader, `Meta.usp_Create_Gold_Views` | warehouse | views expose the new columns | **done** — 366 rows; PBI views now 15 / 11 / 10 cols |
| 10 | **Reconcile against the old chain, before dropping it** | warehouse | every old figure reproduced | **done** — 0 / 0 / 0, re-derived from `Fact_Daily_Targets` as of today |
| 11 | Model: new tables, relationships, RLS, publish, refresh | Desktop | no security-filter errors — save before believing the list | **owner** |
| 12 | Merge `dev` → `main` to deploy the app | CI | Targets screen renders; Home tiles carry targets | |
| 13 | Only now drop `Gold.Fact_Daily_Targets` and its loader | warehouse | — | |

### Where the point of no return is

**Step 7.** `Roles_Are_Client_Wide` collapses role targets held per practice to one per client,
keeping `MIN(Tenant_ID)`'s value where two disagree, and **deletes the losing rows**. Maple has one
practice so there is nothing to collapse there today — 228 role rows all belong to tenant 100 — but
it is still the step that cannot be reversed from the new state alone. Past it, rollback means §2.

Steps 3–6 are nullable `ALTER ... ADD` and reverse cleanly. Steps 0–2 are insert-only.

### Prod is also unbroken between steps 8 and 11 — but only if 8 is split

Step 8 replaces `Gold.Aggregate_Period_Targets` with rev *03, which has different columns. The PBI
views pin their column list at CREATE time and the model's queries name the old ones, so from that
moment until the model is republished at step 11 **the live reports are broken**.

Deploy step 8 in two parts to shrink that window to nothing:

- **8a — additive.** Create `Gold.Dim_Hierarchy_Node` and `Gold.Fact_Node_Targets`, their loader,
  and the new sync proc. Neither table is read by the model, so prod is unaffected, and step 9's
  node loader and step 10's reconcile can both run against the old chain still in place.
- **8b — the switch.** `Aggregate_Period_Targets` rev *03, its loader, `Meta.usp_Create_Gold_Views`,
  then the model publish — **in one sitting**. Do not start 8b without time to finish 11.

### How the step 10 reconcile must be done — and how it was got wrong first

==> DO NOT DIFF THE NEW AGGREGATE AGAINST THE OLD TABLE. <== The first attempt compared today's new
`Aggregate_Period_Targets` against `Backup.Aggregate_Period_Targets__pre_8b`, which the last prod
nightly had built **four working days earlier**. It reported 16 disagreements, all FY26 cumulative
metrics, the new figure about 1.9% higher. None of them were real:

    annual 2,000,000, FY2026 has 261 working days
    new  =  2,000,000 x 216/261  =  1,655,172.4138     (216 = the YTD bucket TODAY)
    old  =  2,000,000 x 212/261  =  1,624,521.0728     (212 = the bucket four working days ago)

Identical arithmetic. The calendar had moved, nothing else. The correct comparison re-derives the
old answer FROM `Gold.Fact_Daily_Targets` over each grouping's own dates, as of now — which is the
entire reason that table is not dropped until step 13. Done that way: **0 cumulative values
differing, 0 non-cumulative figures away from the entered annual, 0 live groupings missing.**

The 112 rows present only in the old table are exactly FY21, FY22 and FY25 — historic buckets the
new chain deliberately excludes and the app's three-period picker could never reach.

### Known, deliberate difference at step 10

A rolling 12-month window carries **262** working days against a financial year's **261**, so a
cumulative target reads about 0.4% above its annual figure on a Last 12 Months tile — £435,000 shows
as £436,667. That is the per-working-day apportionment, and the same arithmetic makes Last 3 Months
come out at roughly a quarter. Expect it; it is not a reconciliation failure.

---

## 5. Rollback by stage

| Failed at | Do this |
|---|---|
| 1–3 | `AppDB.Rollback_Input_Snapshot.sql` with `@tables='ALL'`, then reverse the DDL by hand (drop the PK, drop `Node_Level`/`Node_Key`, recreate the 4-column PK) |
| 4 | Snapshot rollback of `Targets` alone. The schema is fine; only rows moved |
| 5–7 | Nothing in the AppDB changed. Re-deploy the warehouse objects, or restore `Fact_Daily_Targets` and point the model back |
| 8 | Re-publish the previous `.pbix`. Check partition `RefreshedTime` afterwards — a Desktop publish ships its own cached data |
| 9 | Re-deploy the previous container image; the app is stateless |
| anything, totally | `az sql db restore` to a timestamp before step 2, then swap the database over |

**After any AppDB rollback**, the warehouse copy of `Input.*` is still ahead of the truth — it is a
full-refresh copy. Re-run the sync, rebuild `Fact_Node_Targets` and `Aggregate_Period_Targets`, and
refresh the model, or the screens will keep showing the thing you just rolled back.
