---
name: input-rows-live-in-the-appdb-now-azure-sql
description: "Input.* rows must be written to the AppDB (Azure SQL since 2026-09-17), not the warehouse, because the sync full-refreshes the warehouse copy; Web/.env.example points at a dead host."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-14T14:55:43.622Z
---

**Write owner-curated `Input.*` rows to the AppDB, never to the warehouse.**
`Meta.usp_Sync_Input_From_AppDB` does a FULL REFRESH per table -- `DELETE FROM Input.<T>` then
re-`INSERT` from `Input_Stage.<T>` -- so a row written warehouse-side works until the next sync
(every 10 minutes on `caj-appdb-sync-dev`) and then vanishes with no error. `Migrations/V*.sql` is
the wrong vehicle for this: `Scripts/Migrate.ps1` defaults to `WH_Dentally`, so a guarded INSERT
there would be silently undone. Related: [[never-deploy-an-input-table-in-a-release]].

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

**Demo capitation rates, set 2026-10-14:** tenant 12 now carries the group's eight tiers
(plans 4-11, 8.00-65.00, Care Plan C default, hygienist visit 30.00), mirroring tenant 11. Tenant
11 has **Care Plan A at 25.00 in the rate table against 24.00 in its payment-plan definition** -- a
pound of drift in the one place the code comments say the two must agree. t12 uses 24.00, so the
tier sums differ by exactly that: 289.00 against 288.00. Unresolved; needs a decision on which
figure is right. See [[who-counts-as-a-plan-patient]].
