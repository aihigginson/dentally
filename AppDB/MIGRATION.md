# AppDB migration: Fabric SQL Database -> Azure SQL Database

## Why

AppDB has hung repeatedly since it was introduced. On 2026-09-17 both the dev and prod Fabric SQL
Database endpoints stopped accepting connections for ~25 minutes — identical 15.1s
`TCP Provider: Timeout error [258]` on every attempt, from the container apps *and* from a
workstation — while `WH_Dentally` on the **same capacity** answered `SELECT 1` in 0.6s. No Azure
service-health event was published. A capacity pause/resume cleared it, which is the second time
that has been the remedy.

Blast radius when it happens: sign-in and the reports keep working (`_get_user_info` reads
`Security.*` from the **warehouse**), but every Settings screen — subscriptions, billing contact,
targets, variances, roles, practice config — hangs for ~100s and then 500s. That is
`_appdb_conn`'s own retry budget (3 attempts, 30s connect timeout, 5s apart) doing exactly what it
was written to do, because the original design assumed the Fabric SQL DB would *pause when idle*
and need riding out. The failure is not an idle pause: a resume eventually succeeds.

Azure SQL Database is the same engine without the Fabric capacity in front of it. `AppDB/README.md`
already says so: *"Fabric SQL Database = the Azure SQL engine, so full OLTP T-SQL (PK / DEFAULT /
DATETIME2)."* So this is a relocation, not a port.

## What is already built

| | |
|---|---|
| Server | `sql-analytically.database.windows.net` (uksouth, **Entra-only auth** — no SQL login exists) |
| Databases | `AppDB-dev`, `AppDB-prod` — Basic (5 DTU, 2GB), local-redundant backup, ~£4/mo each |
| Firewall | two rules only: the Container Apps env egress IP and the admin workstation. **No allow-all-Azure.** |
| Schema | `AppDB_Input_Schema.sql` applied **unchanged** to both — all 10 `Input.*` tables, PKs and DEFAULTs intact |
| Grants | `ca-analytically-dev` / `ca-analytically-prod` managed identities: `db_datareader` + `db_datawriter`. `analytically-deploy-dev` SP: `db_owner` on dev. |
| Tooling | `Apply_Schema_AzureSql.ps1` (schema + grants, run as Entra admin), `Copy_AppDB.py` (row copy + verify) |
| Data | dev copied and verified — 748 rows across 10 tables, all counts match |

Basic tier is deliberate: the whole dataset is 748 rows. `az sql db update --service-objective S0`
is an online change if it ever throttles.

## The part that is NOT done, and why the order matters

`Meta.usp_Sync_Access_From_AppDB` and `Meta.usp_Sync_Input_From_AppDB` run **inside the warehouse**
and read AppDB by three-part name:

```sql
JOIN [AppDB].[Input].[Application_Users] src ON LOWER(tgt.User_UPN) = LOWER(src.User_UPN)
FROM [AppDB].[Input].[Access_Log] src
```

That resolves only because AppDB is a Fabric item in the same workspace, auto-mirrored to OneLake.
An Azure SQL database is not, so those procs cannot reach it. **Decision: replace the
cross-database read with a pipeline copy** (rather than mirroring Azure SQL back into Fabric) —
fewer Fabric-side moving parts, and the copy is explicit and under our control.

### Order of operations — do not invert these

0. **Populate and VERIFY staging before the procs are repointed.** `usp_Sync_Input_From_AppDB`
   DELETEs-then-INSERTs six `Input.*` tables, so running it against an empty `Input_Stage` wipes
   the tenant's targets, practitioner roles, pay, plan rates and practice config. On dev this was
   survived by luck -- staging happened to be full already. On prod it was done deliberately:
   copy -> populate -> `EXCEPT` both directions against `[AppDB].[Input].[X]` -> only then V161.
   The job's own NONEMPTY floor protects the JOB from an empty source; it does not protect the
   PROC from empty staging when something else runs it, such as the nightly pipeline.

1. **Pipeline copy first.** A Fabric Data pipeline Copy activity: Azure SQL `Input.*` ->
   `WH_Dentally.Input_Stage.*`. Then repoint the two sync procs from `[AppDB].[Input].[X]` to
   `Input_Stage.[X]`. Their MERGE logic is unchanged — only the source name moves.
2. **App cutover second.** Repoint `APPDB_SERVER` / `APPDB_DB` on the container app.

Inverting them silently breaks access control: the app would write subscription changes to Azure
SQL while the warehouse kept syncing `Security.*` from the now-stale Fabric AppDB, so a newly
subscribed user would never gain access and a revoked one would keep it. Auth reads the warehouse,
so the damage would not show up on the screen that made the change.

3. **Verify per environment** — dev fully, including a subscription change end-to-end through
   `usp_Sync_Access_From_AppDB`, before touching prod.
4. **Decommission** the Fabric SQL DB items only after a full build cycle has run clean.

### Known trap

Fabric **Script/Copy activities do not repoint on promotion** — a named connection survives
dev -> prod deployment, and prod pipelines have silently run against dev before (see project
memory `fabric-script-activities-dont-repoint`). The new Copy activity must have its connection
checked *in prod, after promotion*, not assumed.

## Status

**dev: cut over** (2026-09-17). App -> `AppDB-dev`, `caj-appdb-sync-dev` on `*/10`, procs reading
`Input_Stage`, `Security.Application_Users` steady at 19.

**prod: cut over** (2026-09-17). App -> `AppDB-prod`, `caj-appdb-sync-prod` on `*/10`, procs
reading `Input_Stage`, `Security.Application_Users` steady at 7. Staging verified row-for-row
against the old Fabric source before V161 (all eight tables, `EXCEPT` zero both ways).

### OUTSTANDING: the prod job runs a dev-built image

`caj-appdb-sync-prod` is pinned to `analytically:11fb4716...`, a digest-tagged image built from
the `dev` branch. `analytically:latest` (built from `main`) does not contain `appdb_sync.py` at
all, because the script has never been merged, so the job failed with
`can't open file '/app/appdb_sync.py'` until it was repointed.

This is safe -- the script's target is decided entirely by env vars, and the prod job carries prod
env vars -- but it is exactly the kind of temporary pin that gets forgotten. **Repoint it to
`analytically:latest` once `dev` is merged to `main`.**

Merging is itself blocked on prod warehouse releases: **V159** (`Stripe_Customer_ID`) must land
first, or `/api/stripe/payment-method` queries a column that does not exist and 500s the Invoices
tab. **V162** (VAT-inclusive prices) should land in the same batch, or prod will label net prices
"inc. VAT" on a public endpoint.

## Cutover checklist (per environment)

- [ ] Pipeline copy built and running into `Input_Stage.*`
- [ ] Both sync procs repointed and deployed via a release manifest
- [ ] Sync verified: change a subscription, confirm `Security.Application_Users` follows
- [ ] Writes quiesced (nobody on Settings), then `Copy_AppDB.py --env <env> --copy` for the final pass
- [ ] `APPDB_SERVER` / `APPDB_DB` repointed on the container app; confirm env var count before/after
- [ ] Smoke: Subscriptions, Invoices, Targets, Variances, Roles all load and save
- [ ] `_appdb_conn`'s retry comment updated — the "pauses when idle" rationale no longer applies,
      and the 100s budget should come down once the endpoint is a normal Azure SQL one
