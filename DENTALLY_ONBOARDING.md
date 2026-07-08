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

## Initial full load (run `Ingest_Dentally` STANDALONE, not via Orchestrate)

The first pull is big (~1.9M records) and Dentally's rate limit makes it a **multi-hour,
overnight job**. Do NOT run it through `Orchestrate_Build` -- CELL 7c calls it via
`notebook.run(..., 3600, ...)`, a hard 1-hour timeout it will blow past. Instead:

1. Open `Ingest_Dentally` directly (LH_Dentally attached as default), set `sample_pages = 0`,
   `only_tenant = "100"`, and run it. A directly-run notebook has no child-timeout; its
   Spark session can run for hours.
2. When it finishes, run `Orchestrate_Build` with `run_dentally_ingest = False`,
   `tenants_override = [100]` -- it just builds Bronze->Gold from the landed stage.
3. Nightly after that = incremental: `full_refresh = False` pulls only changes via
   `updated_after` from `Last_Loaded_At` -- small and fast, safe inside Orchestrate's timeout.

### Dentally rate limit (confirmed against the live API)
- **3,600 requests / clock-hour** (`x-ratelimit-limit: 3600`), reset = unix epoch on the
  top of each hour. That's **1 request/second** -- the initial backfill is bound by this.
- **Draining the budget to 0 gets a `403` temp-block** (not 429). The notebook now sleeps to
  the hourly reset when the budget nears zero (`RATE_FLOOR`), so it **can't hit 0** -- it will
  visibly pause between hourly windows. That is correct, not a hang.
- **`per_page` max is 100** -- asking for more silently drops to 25 (more calls). Leave at 100.
- The whole 1.9M pull is ~23-25k calls => ~7 hourly windows. **Ask Dentally to raise the rate
  limit for the initial migration** -- that's the single biggest lever (collapses it to ~1h).

### Resume a partial run (`only_entities` -- also sets the ORDER)
If a run stops part-way, the entities already printed are safely in `stage_*` (tenant-scoped).
Re-pull ONLY the rest -- and in the order you list -- with `only_entities`:
```
only_entities = ["treatment_plan_items","treatment_plans","recalls","nhs_claims",
                 "patient_stats","treatment_appointments","patient_referrals","fees"]
```
(Put the ones you care about most FIRST -- e.g. `treatment_plan_items` -- so you reach them
before the long tail. `[]` = every entity in registry order.)

---

## Promote a practice DEV -> PROD (option B: copy stage, no re-pull)

The initial pull is expensive, so we pull ONCE (in dev) and copy the raw stage layer to prod
rather than re-hitting Dentally. Uses `Fabric/Notebooks/Promote_Tenant_Stage.ipynb`.

> **CRITICAL ORDER -- copy stage BEFORE any incremental.** `write_stage` overwrites the whole
> tenant partition (`replaceWhere tenant_id`), so an incremental leaves stage holding ONLY the
> delta -- which would then be all that gets copied. Sequence: full load -> **copy stage** ->
> build prod -> only THEN run incrementals (and run them in PROD, where Bronze persists them).
> Belt-and-braces: run dev `Orchestrate_Build` (`run_dentally_ingest=False`) once after the
> full load to persist the full set into dev Bronze before copying. Ensure any SCHEDULED dev
> build has `run_dentally_ingest=False` so it can't fire an incremental and clobber stage.

1. **Import `Promote_Tenant_Stage`** into the **prod** workspace; attach prod **`LH_Dentally`**
   as default (re-pin after every import).
2. **Copy the stage (run in PROD):** params `mode="copy"`, `tenant_id=100`,
   `source_workspace="<dev workspace name or GUID>"`. Reads dev's `stage_*` over OneLake and
   writes tenant 100's rows into prod stage (tenant-scoped `replaceWhere`).
3. **Register the tenant in prod** `Audit.Tenants` (same INSERT as the dev step above).
4. **Build prod from the copied stage:** run prod `Orchestrate_Build` with
   `run_dentally_ingest=False`, `tenants_override=[100]` -> Bronze->Gold + model refresh.
   Verify the prod reports.
5. **Ongoing incrementals:** load the token into `dentally-tokens-prod`, then set prod nightly
   `run_dentally_ingest=True`, `full_refresh=False` -> prod pulls only changes (cheap) from now on.

### Then purge dev (real data must not linger in dev)
6. **Purge dev stage (run in DEV):** `Promote_Tenant_Stage` `mode="purge"`, `tenant_id=100`,
   `confirm_purge=True` -> deletes tenant 100 from every dev `stage_*` Delta table.
7. **Purge dev warehouse:** `EXEC Audit.usp_Delete_All_Tenant @Tenant_ID=100, @Dry_Run=1` to
   preview, then `@Dry_Run=0` -> clears Bronze/Silver/Gold + the Audit.Tenants row. (This SP
   does NOT touch stage -- step 6 covers that.)

---

## Known data-shape fixes (surfaced on the first real build)

- **Silver/Gold numeric casts (FIXED, V041):** real Dentally puts non-numeric strings in
  fields the mock kept numeric -- `payment.transaction_number` = Stripe ids (`ch_...`) broke a
  hard `float` cast (8114); alphanumeric treatment `code` (`DOMI`) broke an `int` cast (245).
  Swept to `TRY_CAST` across 18 Silver procs + fixed `Dim_Treatments`. Deploy V041.
- **`accounts` + `waiting_lists`:** these DO exist as Dentally endpoints and are now in the
  ingest registry (earlier "no endpoint" note was wrong).
- **`stage_payment_allocations` (open):** real Dentally nests allocations in
  `payment.explanations[]` (landed as `stage_payment_explanations`). Confirm whether a
  standalone `/payment_allocations` endpoint also exists, or point that Bronze load at the
  explanations.
- **`invoice_items.nhs_charge` (open, data-correctness not a blocker):** it's a **boolean**
  (is-NHS flag) but `Gold.Fact_Invoice_Items.NHS_Charge` is `decimal(12,2)`. `TRY_CAST` makes
  it NULL rather than error -- fix the mapping (make it a flag, or drop) once we see it flow.

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
