---
name: input-rows-live-in-the-appdb-now-azure-sql
description: "Input.* rows must be written to the AppDB (Azure SQL since 2026-09-17), not the warehouse, because the sync full-refreshes the warehouse copy; Web/.env.example points at a dead host."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-29T15:32:22.665Z
---

**Write owner-curated `Input.*` rows to the AppDB, never to the warehouse.**
`Meta.usp_Sync_Input_From_AppDB` does a FULL REFRESH per table -- `DELETE FROM Input.<T>` then
re-`INSERT` from `Input_Stage.<T>` -- so a row written warehouse-side is overwritten the next time
the sync runs, with no error.

==> ON DEV THE SYNC IS DISABLED, AND MUST BE RUN BY HAND BEFORE A REBUILD. <== Owner, 2026-10-14.
`AppDB/MIGRATION.md` advertises `caj-appdb-sync-dev on */10` and that is NOT live on dev -- do not
assume a rate or target set in the AppDB has reached the warehouse. Run it first or capitation and
targets silently compute against stale Input tables:

```
python Web/appdb_sync.py check   # report both sides, copies nothing
python Web/appdb_sync.py full    # stage all 8 tables, then Meta.usp_Sync_Input_From_AppDB
```

`full` is the pre-rebuild mode; `access` is the 10-minute one and runs a different proc.
`Web/.env` has no `APPDB_*` keys, so supply `APPDB_SERVER` / `APPDB_DB` when running it locally.

`Migrations/V*.sql` is the wrong vehicle for setting these rows: `Scripts/Migrate.ps1` defaults to
`WH_Dentally`, so a guarded INSERT there lands warehouse-side and the next sync undoes it.
Related: [[never-deploy-an-input-table-in-a-release]].

**The AppDB is AZURE SQL, not Fabric SQL DB** -- migrated 2026-09-17 (`AppDB/MIGRATION.md`):

```
sql-analytically.database.windows.net   /  AppDB-dev     (and AppDB-prod)
```

==> `Web/.env.example` IS STALE AND WILL WASTE YOUR TIME. <== It still advertises the old Fabric
endpoint `...-4i26eirspjiujnltrvplquzkem.database.fabric.microsoft.com` /
`AppDB-4c31e989-...`, which no longer resolves at all -- "No such host is known". `Web/.env` has no
`APPDB_*` keys either (the app reads them from Key Vault when deployed), so there is nothing local
to copy. The live endpoints are in `AppDB/Copy_AppDB.py`.

**Auth is the same SP token as the warehouse** (`FABRIC_SP_*` from `Scripts/fabric_creds.local.ps1`,
scope `https://database.windows.net/.default`), and the SP is already a user in `AppDB-dev`. So
these rows can be set directly -- going through the app UI is one route, not the only one. Verify
identity read-only first (`SELECT DB_NAME(), SUSER_SNAME()` plus a known tenant's rows) before any
write, which is what caught the dead endpoint rather than a half-applied change.

==> **DDL ON THE APPDB NEEDS NOBODY'S HELP. DO NOT HAND A MIGRATION BACK.** <== Measured
2026-10-29 on `AppDB-dev`: `USER_NAME()` = `dbo`, `IS_MEMBER('db_owner')` = 1,
`IS_MEMBER('db_ddladmin')` = 1. `ALTER TABLE` works.

```
python appdb_run.py dev <file.sql>     # GO-split; scratchpad helper
```

The confusion to avoid: **`appdb_run.py` authenticates with the OWNER'S DELEGATED token**
(`az account get-access-token`), not with `FABRIC_SP_*`. The "data rights only, no DDL" limit is
real but belongs to the **app's service principal** -- a different identity. Conflating the two
cost the owner two hand-offs in one day (`AppDB.Migration.Client_Keying.sql`, then
`AppDB.Migration.Top_Node.sql`) before they pushed back: *"you definitely have been doing DDL
changes to AppDB"*. They were right. Same shape as
[[prod-warehouse-deploy-from-the-laptop]] -- a delegated token, not a bypass.

Ordering still matters, for a different reason: `appdb_sync` takes its column list from the
**target** (`Input_Stage`), so add a column to the AppDB FIRST. Warehouse-first makes the source
`SELECT` name a column the AppDB lacks, and that job reports SUCCEEDED while failing
([[container-job-failures-are-unmonitored]]).

**Demo capitation rates, set 2026-10-14:** tenant 12 now carries the group's eight tiers
(plans 4-11, 8.00-65.00, Care Plan C default, hygienist visit 30.00), mirroring tenant 11. Tenant
11 has **Care Plan A at 25.00 in the rate table against 24.00 in its payment-plan definition** -- a
pound of drift in the one place the code comments say the two must agree. t12 uses 24.00, so the
tier sums differ by exactly that: 289.00 against 288.00. Unresolved; needs a decision on which
figure is right. See [[who-counts-as-a-plan-patient]].
