# Runbook — Analytically (Dentally DW + SaaS embed)

Operational guide: environments, how to deploy, the golden rules, and an incident
playbook for the failures we've actually hit. Pairs with [ROADMAP.md](ROADMAP.md)
and [EVALUATION.md](EVALUATION.md).

> Secrets are **never** in this file or git. SP/app secrets live in the Container
> App config and `Scripts/fabric_creds.local.ps1` (gitignored). Endpoints, GUIDs
> and resource names below are infrastructure identifiers, not secrets.

---

## 1. Environments

Dev and prod are **separate Fabric workspaces + warehouses** (same capacity).

| | Dev | Prod |
|---|---|---|
| Web app (Azure Container App) | `ca-analytically-dev` | `ca-analytically-prod` |
| URL | https://dev.analytically.info | https://analytically.info |
| Image tag deployed | `:<git-sha>` (also builds `:dev`) | `:<git-sha>` (also builds `:latest`) |
| Fabric workspace | `22e235e2-7a32-4451-b573-8d5eb8532a23` | `2490d322-e8cc-4e9e-a3dc-964ce6fe444f` |
| Warehouse SQL endpoint | `…-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com` | `…-eljzajgm5cpe5i64szgon7sej4.datawarehouse.fabric.microsoft.com` |
| Warehouse DB | `WH_Dentally` | `WH_Dentally` |

- Resource group `rg-analytically` (UK South); ACR `analyticallyacr.azurecr.io/analytically`.
- App reads its warehouse from env vars `FABRIC_SERVER` / `FABRIC_DB`; PBI workspace/dataset/report IDs are also env vars (prod-specific).
- The git **`dev`** branch deploys to dev; **`main`** deploys to prod.

---

## 2. Deploying

### 2a. Web app (CI/CD — automatic)
- Push to **`dev`** with `Web/**` changes → `deploy-dev.yml` builds + deploys `:<sha>` to `ca-analytically-dev`.
- Merge `dev` → **`main`** with `Web/**` changes → `deploy-prod.yml` runs the **`dw-tests` gate**, then builds + deploys `:<sha>` to `ca-analytically-prod`.
- No `Web/**` changes in the merge ⇒ no web deploy triggered (correct).
- Merging `dev`→`main` when `.pbix`/other files are live-modified: use a **git worktree** to merge (never `git checkout` with uncommitted `.pbix`).

### 2b. Warehouse (manual, deliberate)
Warehouse schema/data is managed by **versioned manifests**, NOT the Fabric deployment pipeline:
```powershell
# dev (default endpoint)
.\Scripts\Deploy.ps1 -Manifest Releases\Vnnn__<name>.manifest
# prod
$env:FABRIC_SERVER = '…-eljzajgm5cpe5i64szgon7sej4.datawarehouse.fabric.microsoft.com'
$env:FABRIC_DB     = 'WH_Dentally'
.\Scripts\Deploy.ps1 -Manifest Releases\Vnnn__<name>.manifest
```
- Manifest tags: `MIGRATE` (once-only schema delta, tracked in `Migrate.Schema_Version`), `DEPLOY` (idempotent object/seed), `EXEC` (inline T-SQL / proc run), `TEST` (run `Run_Tests.ps1` gate).
- Every run is stamped in `Migrate.Deploy_Log` (manifest, git sha, who, when, status).
- Auth: Test Runner SP via `Scripts/fabric_creds.local.ps1`. CI uses `deploy-warehouse.yml` (workflow_dispatch).

### 2c. PBI semantic model + reports
- Promoted dev→prod via the **Fabric deployment pipeline**, with a **parameter rule** setting `pServer`/`pDatabase` to the prod warehouse.
- After any warehouse data change, **refresh the prod semantic model**.

### Rollback
- **Web:** redeploy a prior commit's image — `az containerapp update -n ca-analytically-prod -g rg-analytically --image analyticallyacr.azurecr.io/analytically:<old-sha>`. (Deterministic because we deploy `:sha`.)
- **Warehouse:** forward-only. Revert the offending object file + ship a new `Vnnn` manifest. See `Releases/README.md`.

---

## 3. Golden rules (learned the hard way)

1. **Keep the warehouse OUT of the Fabric deployment pipeline.** The pipeline copies object *definitions* only — it creates **empty** tables and does **not** run load SPs or copy seed data, and it competes with the SQL deploys as a second source of truth. Manage the warehouse solely via `Vnnn` manifests.
2. **Parameterise the semantic-model source** (`pServer`/`pDatabase`). Every table must resolve through the *same* parameterised `Sql.Database(pServer, pDatabase)` source. A **named connection** (even to the same server) is invisible to the pipeline's parameter rule and won't repoint on promotion.
3. **Deploy `:sha`, never `:latest`.** A mutable tag drifts from the running code → an env/config change can break a stale image at boot (see incident A).
4. **Env/secret changes must ship with a compatible image.** Removing an env var the running image still requires = crash loop. Update code + image together, on **both** `:dev` and `:latest`/`:sha`.
5. **Every tenant-bearing table needs the RLS filter.** `Scripts/Check_RLS_Coverage.ps1` enforces this; a new table with a `Tenant ID` column and no filter is a silent cross-tenant leak.

---

## 4. Incident playbook

### A. Prod app down / "stream timeout" / HTTP 000
- **Check revisions:** `az containerapp revision list -n ca-analytically-prod -g rg-analytically --query "[?properties.active].{name:name,health:properties.healthState,running:properties.runningState,traffic:properties.trafficWeight,img:properties.template.containers[0].image}" -o table`
- **Check boot logs:** `az containerapp logs show -n ca-analytically-prod -g rg-analytically --tail 40` — a Python `KeyError: 'X'` at import = a required env var is missing for the running image.
- **Fix:** deploy an image whose code matches the current env (rebuild from current `Web/` via `deploy-prod.yml`, or `az containerapp update --image …:<good-sha>`). Don't re-add a removed secret just to satisfy a stale image.

### B. Prod app shows wrong / dev data
- The app's **`FABRIC_SERVER`** is pointing at the wrong warehouse. Check: `az containerapp show -n ca-analytically-prod -g rg-analytically --query "properties.template.containers[0].env[?name=='FABRIC_SERVER'].value | [0]" -o tsv`. Prod must be the `…-eljz…` endpoint.
- Embedded reports showing wrong data instead = the **semantic model** data source (parameter rule / connection), not the app.

### C. New table empty in prod after promotion
- The Fabric pipeline created the object but didn't populate it. Run the `Vnnn` manifest for that feature against prod (it runs the load SP + any reload), then refresh the model. (Rule 1.)

### D. App / reports blank for everyone
- Expected fail-closed state when `Audit.Tenants` is empty: RLS resolves no tenants. The access chain is `Security.Application_Users` (UPN→Client_ID) → `Security.Clients` → `Audit.Tenants` (Tenant_ID→Client_ID). Seed those (per environment) to grant access.

### E. RLS gate fails (coverage or isolation)
- `Check_RLS_Coverage.ps1` lists unfiltered tenant-bearing tables → add the RLS filter in the model. `Check_RLS_Isolation.ps1` proves a user sees only their tenant (needs the Test Runner SP as workspace **Admin**).

---

## 5. Diagnostics

- **Warehouse active requests** (read-only, as the SP): `SELECT session_id,status,command,start_time,total_elapsed_time/1000 elapsed_sec FROM sys.dm_exec_requests WHERE status NOT IN ('background') ORDER BY total_elapsed_time DESC`. **Long-running `SELECT`s with `program_name='QueryInsights'` / `wait_type='XE_LIVE_TARGET_TVF'` are benign** Fabric telemetry, not a blockage.
- **Web health:** `curl https://<env>.analytically.info/health` → `{"status":"ok"}`.
- **Read-only warehouse spot-checks:** connect with the Test Runner SP (client-credentials token, `.NET SqlClient`, `Encrypt=True`) — see the pattern in `Scripts/Deploy.ps1`.
- **CI runs:** GitHub Actions — `deploy-dev.yml`, `deploy-prod.yml`, `dw-tests.yml`, `deploy-warehouse.yml`.

---

## 6. Access control (RLS)

- Model RLS role `RLS`; embed token always attaches the effective identity (fail-closed; unprovisioned UPNs get 403).
- Mapping: `Application_Users.User_UPN → Client_ID`, `Clients.Client_ID`, `Audit.Tenants(Tenant_ID, Client_ID)`. A user sees their client's tenants.
- These three tables are **environment-specific** and managed **out of git** (dev values must never ship to prod). `Audit.Tenants` also holds per-tenant Dentally API secrets — keep them in a gitignored local `.sql`, never committed.
- The invariant control/config seeds (Process_Config/Dependency, Config.*, reason map, Test.* defs) ship via `Releases/V000__metadata_seed_baseline.manifest`.
