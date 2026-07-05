# Dentally Onboarding & Operations Runbook

How to connect a **real** dental practice's Dentally and get its data flowing into the
model, replacing the mock/synthetic tenants. The recurring pull runs **in Fabric** (the
`Ingest_Dentally` notebook, inside the nightly `Orchestrate_Build`); the only manual step
per practice is getting the OAuth token and registering the tenant.

Architecture (source-of-truth: `project_dentally_go_live` memory + `DENTALLY_RECONCILIATION.md`):
```
Dentally OAuth token  ->  Key Vault secret: dentally-tokens-<env>
                                   |
Orchestrate_Build (nightly, Fabric)v
  CELL 7c: Ingest_Dentally  --reads KV-->  api.dentally.co  -->  stage_* (Delta)
     flatten .user/.site + payment.explanations[] + rota.breaks[]; DROP PII (V011/V012)
  DAG waves: BRONZE_* -> SILVER_* -> GOLD dims/facts/aggs   (auto via Process_Config)
  -> semantic model refresh
```

Lands the **same `stage_*` table names the mock produced**, tenant-scoped by `replaceWhere`,
so real practices (Tenant 100+) coexist with the synthetic tenants (11-14) and the existing
Bronze/Silver/Gold build runs unchanged.

---

## Confirmed environment

| Thing | Value |
|---|---|
| Key Vault | `kv-analytically` -- `https://kv-analytically.vault.azure.net/` |
| Pipeline run identity | `admin@analytically.info` -- dev **and** prod `Orchestrate_Build` run as this; already has get/set on the vault |
| Notebook -> KV auth | `notebookutils.credentials.getSecret(...)` -- confirmed works (same as Ingest_Xero) |
| API base | `https://api.dentally.co/v1` (`practice` is a single object; appointments/rota need `after`/`before`) |

Key Vault secret (per-environment so dev and prod client data never mix):
| Secret | Shape | Status |
|---|---|---|
| `dentally-tokens-<env>` | `{"<Tenant_ID>": {"token": "...", "base_url": "https://api.dentally.co/v1", "name": "..."}}` | `-dev` has `100` (Maple Dental) |

---

## One-time setup (do once)

1. **Import the notebooks** into the Fabric **dev** workspace (Workspace -> Import -> Notebook):
   - `Fabric/Notebooks/Ingest_Dentally.ipynb` (new)
   - `Fabric/Notebooks/Orchestrate_Build.ipynb` (changed -- now has the `run_dentally_ingest`
     param + CELL 7c). Re-import to overwrite the existing one.
   (Repeat into **prod** when a real practice goes to prod.)

   **Attach the Lakehouse:** on `Ingest_Dentally`, add **`LH_Dentally`** and set it as the
   **default** lakehouse (Explorer -> Add lakehouse -> LH_Dentally -> Set default). The
   notebook writes `stage_*` via `saveAsTable`, which targets the default lakehouse -- with
   none attached the writes fail. (Same requirement as the mock `Stage_Ingest` and `Ingest_Xero`.)
   The attachment sticks when `Orchestrate_Build` calls it via `notebook.run`. No Warehouse
   attachment needed (it does no T-SQL).

2. **Confirm the token is in Key Vault** (already loaded for Maple Dental in dev):
   ```
   az keyvault secret show --vault-name kv-analytically --name dentally-tokens-dev --query value -o tsv
   ```
   Should show `{"100": {"token": "...", "base_url": "https://api.dentally.co/v1", "name": "Maple Dental"}}`.

3. **Register the tenant** in `Audit.Tenants` (Tenant 100 is in `Audit.Tenants.Data.sql`; the
   seed does DELETE + re-INSERT, so to add it WITHOUT disturbing the other rows run this one-off
   in the dev Warehouse SQL editor):
   ```sql
   DELETE FROM Audit.Tenants WHERE Tenant_ID = 100;
   INSERT INTO Audit.Tenants
     (Tenant_ID, Client_ID, Tenant_Name, API_Base_URL, API_Key, Dentally_Client_ID, Dentally_Secret, Is_Active, Full_Refresh, Last_Loaded_At, Notes)
   VALUES
     (100, 100, 'Maple Dental', 'https://api.dentally.co/v1', NULL, NULL, NULL, 1, 1, NULL, 'REAL - first live practice. Token in Key Vault dentally-tokens-dev.');
   ```

---

## Smoke test (prove the path before the full pull)

In the dev `Orchestrate_Build` parameters set:
```
run_dentally_ingest   = True
dentally_sample_pages = 2          # cap: ~200 rows/entity, fast
tenants_override      = [100]      # build ONLY the real tenant
run_stage_ingest      = False      # don't also hit the mock API
run_xero_ingest       = False
full_refresh          = True
```
Run it. Expected: CELL 7c prints `Ingest_Dentally (all mapped practices)` then each entity
`... rows -> stage_<name>`; then the DAG runs `BRONZE_* -> SILVER_* -> GOLD` for tenant 100
and refreshes the model. **Send me the output** -- especially any FAILED Bronze job (that's
where the 3 known stage gaps below will surface, and I'll fix them).

## Full load

Once the smoke test is clean: set `dentally_sample_pages = 0` (full pull) and run again.
NOTE: the full pull is ~1.9M records + 113k appointments -- the `notebook.run` timeout is
3600s and may be tight; if it times out we raise it or switch that tenant to incremental
(`full_refresh = False`, which pulls via `updated_after` from `Last_Loaded_At`).

---

## Known gaps to resolve on the first real Bronze run

The mock also fed three stage tables the real API doesn't map cleanly. If the matching
Bronze load FAILS on a missing stage table, that's expected -- report it and I'll fix:
| stage table | issue | fix |
|---|---|---|
| `stage_accounts` | no confirmed real `/accounts` endpoint | derive from `patient.account_id`, or make the Bronze load tolerant |
| `stage_waiting_lists` | endpoint not surveyed | probe `/waiting_lists`; or skip if the practice doesn't use them |
| `stage_payment_allocations` | real nests allocations in `payment.explanations[]` | point the Bronze load at `stage_payment_explanations`, or split the fields |

Also on first real data: `invoice_items.nhs_charge` is a **boolean** (is-NHS flag) but
`Gold.Fact_Invoice_Items.NHS_Charge` is `decimal(12,2)` -- a Silver/Gold mapping fix
(make it a flag, or drop) once we see it flow.

---

## Verify / troubleshoot

- **`stage_*` tables gain `tenant_id = 100` rows** = the pull + land worked.
- **`kv_get` returns empty / SystemExit** = `dentally-tokens-dev` missing or wrong env param.
- **An entity returns 0 rows unexpectedly** = check `after`/`before` (appointments/rota) or
  that the practice has that feature (rooms=0 and empty rota are normal for some practices).
- **429 / rate pauses in the log** = expected on a big pull; the notebook backs off automatically.
- Reconciliation blueprint for every entity: `DENTALLY_RECONCILIATION.md`.

---

## Known follow-ups (not blockers)

- **Self-serve "Connect Dentally" button** in the embed app (step A) -- mirrors Connect Xero,
  replaces the manual token load once ingestion is proven.
- **Run the pipeline under a workspace identity / SP** instead of `admin@analytically.info`.
- **Incremental extraction** via `updated_after` after the first full load (cost, not urgent).
