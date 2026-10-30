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

## 3. A blocker that is not about backups

**The prod hierarchy is empty, and the new chain produces nothing without it.**

Measured on prod:

- `Input.Targets` has **none** of `Client_ID`, `Level_Type`, `Level_Key` — `AppDB.Migration.Client_Keying.sql`
  has never run there.
- `Input.Client`, `Client_Tenant`, `Client_Region`, `Client_Area`, `Site_Area` are **all empty**, in
  both the AppDB and the warehouse copy.
- `Security.Clients` *does* have Maple — client **100** `Maple Dental` (also 1 `Analytically` and
  1000 `Maple Dentalcare Ltd`; the tenant maps to **100**, not 1000).
- `Gold.Dim_Hierarchy_Node` and `Gold.Fact_Node_Targets` do not exist on prod; `Gold.Fact_Daily_Targets`
  still does; `Gold.Aggregate_Period_Targets` holds 478 rows from the old chain.

`Gold.usp_Load_Fact_Node_Targets` builds its tree from
`Input.Client_Region → Client_Area → Site_Area → Dim_Practice_Sites`. With those empty it produces
**zero nodes and zero targets**, and because `Client_Keying` backfills `Client_ID` *from*
`Input.Client_Tenant`, running it against an empty map leaves every target's `Client_ID` NULL — and
the loader skips `Client_ID IS NULL`.

So Maple's 334 targets would vanish from every report. Not lost — still in `Input.Targets` — but
invisible until the bridge is populated.

**What prod needs seeding with**, before anything else: client 100 → tenant 100 in `Input.Client_Tenant`,
one region, one area under it, and Maple's site mapped to that area. The region and area *names* never
appear anywhere: Maple has one site, so the fold keeps only its Practice node and discards Region,
Area and Client. It is mechanical, but it is the owner's data — **I have not written it.** `AppDB/Seed_Hierarchy_Dev.sql`
is the dev equivalent to model it on.

---

## 4. Release order

Each step says what proves it worked. **Stop at the first gate that fails** — everything before the
point of no return is cheap to undo.

| # | Step | Gate |
|---|---|---|
| 0 | `Backup_AppDB.py AppDB-prod`, then `AppDB.Backup_Input_Snapshot.sql` | manifest verified; snapshot counts match live |
| 1 | Seed the prod hierarchy (§3) | `Input.Client_Tenant` maps 100→100; `Site_Area` has Maple's site |
| 2 | `AppDB.Migration.Client_Keying.sql` | its own check: 0 unmapped rows on every table |
| 3 | `AppDB.Migration.Target_Node_Key.sql` | PK lists 6 key columns; rows = distinct addresses |
| 4 | **`AppDB.Migration.Roles_Are_Client_Wide.sql`** | role rows at `('Practice','100')`; `All Roles` count unchanged at 179 |
| 5 | Warehouse: deploy the new tables and loaders, run `Meta.usp_Create_Gold_Views` | views expose the new columns |
| 6 | Run the AppDB sync, then `usp_Load_Fact_Node_Targets`, then `usp_Load_Aggregate_Period_Targets` | `Dim_Hierarchy_Node` has Maple's one node; period rows > 0 for client 100 |
| 7 | Reconcile against the old chain **before dropping it** | every old `Aggregate_Period_Targets` figure reproduced |
| 8 | Model: the new tables, relationships, RLS, then publish and refresh | no "security filter expressions have errors"; save before believing the error list |
| 9 | App deploy | Targets screen renders; Home tiles carry targets |
| 10 | Only now drop `Gold.Fact_Daily_Targets` and its loader | — |

### Where the point of no return is

**Step 4.** `Roles_Are_Client_Wide` collapses role targets held per practice down to one per client,
keeping `MIN(Tenant_ID)`'s value where two practices disagree. The losing rows are **deleted**, and
nothing in the new schema records what they were. Maple has one practice so there is nothing to
collapse there *today* — but the step is still the one that cannot be reversed from the new state
alone. Past it, rollback means §2.

Steps 2 and 3 are additive (`ALTER ... ADD`, a widened key) and reverse cleanly. Step 1 is insert-only.

### A caution on step 7

Reconcile *before* step 10, not after. `Fact_Daily_Targets` is the only thing that can prove the new
figures match the old ones, and once it is dropped the comparison is gone. On dev this reconciled
exactly: 0 rows only in old, 0 only in new, 0 values differing — one NHS row at 1828.7356 vs
1828.7357, which is rounding.

### Known, deliberate difference

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
