# AppDB — Fabric SQL Database (target-model OLTP backend)

Transactional store for the owner-curated target Inputs (`Input.Practitioner_Role`,
`Input.Targets`, `Input.Metric_Variance`). The Settings screens read/write here for instant
CRUD; Fabric mirrors it to OneLake; Orchestrate_Build copies it into `WH_Dentally.Input.*` for
the target-fact builds. Design: `../.claude/plans/target-model-redesign.md`. Build plan:
`../.claude/plans/target-model-build-plan.md`.

Why not the warehouse: the Fabric Warehouse is OLAP columnstore on a smoothed F2 — multi-second
per-row read/write. This DB is the Azure SQL (OLTP) engine: millisecond point CRUD, real PKs/DEFAULTs.

## Phase 0 spike — provisioning (your steps, in the Fabric portal)

1. **Create the SQL Database.** Dev workspace → **New item → SQL database**. Suggested name: `AppDB`
   (one per env; create a prod one later the same way). Note it consumes the shared F2 capacity —
   trivial for this CRUD load.
2. **Get the connection details.** Open the DB → **Settings → Connection strings** (or the ⚙ / "…"
   menu). Copy the **Server** (FQDN, ends `.database.fabric.microsoft.com`) and the **Database** name.
3. **Grant the deploy SP access** so the harness can connect. In the DB's **query editor** (you're the
   creator/admin), run:
   ```sql
   CREATE USER [analytically-deploy-dev] FROM EXTERNAL PROVIDER;   -- the dev deploy SP (app id f69d251c)
   ALTER ROLE db_owner ADD MEMBER [analytically-deploy-dev];
   ```
   (Use the SP's Entra display name; if name lookup fails, use its app id.)
4. **Hand me the Server + Database.** Then I run the harness below.

## Prove both pipes

```powershell
.\AppDB\Provision_And_Test.ps1 -Server '<fqdn>' -Database 'AppDB'
```
Applies `AppDB_Input_Schema.sql` (idempotent) and runs an insert→read→delete smoke test on a
throwaway tenant (999). "SPIKE PASS" = the app→SQL-DB pipe works. Then we design the copy step
(SQL DB → `WH_Dentally.Input.*`) to close the warehouse pipe.

## Later (Phase 4) — app auth
The app connects via the Container App **managed identity** (not the SP). Grant it the same way:
`CREATE USER [<managed-identity-name>] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader/db_datawriter ...`
(mirrors the Xero-token managed-identity pattern). Read/write only — not db_owner.
