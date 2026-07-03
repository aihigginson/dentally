# Xero Onboarding & Operations Runbook

How to connect a practice's **Xero** and get its costs/margin flowing into the model.
The recurring pull runs **in Fabric** (the `Ingest_Xero` notebook, inside the nightly
`Orchestrate_Build`); the only manual step is the one-time OAuth consent per practice.

Architecture (source-of-truth: [[project_xero_integration]] memory):
```
xero_auth.py (one-time consent)  ->  Key Vault secret: xero-tokens
                                            |
Orchestrate_Build (nightly, Fabric)        v
  CELL 7b: Ingest_Xero  --reads KV-->  Xero API  -->  stage_xero_* (Delta)
  DAG waves: BRONZE_XERO_* -> SILVER_XERO_* -> GOLD Fact_Finance   (auto via Process_Config)
  -> semantic model refresh
```

Data grain: Practice-Site x Period x GL-account (aggregate finance, not patient-level).
Document-based (NOT the gated `accounting.journals.read`) — reconciles to Xero's P&L.

---

## Confirmed environment (2026-07-03)

| Thing | Value |
|---|---|
| Key Vault | `kv-analytically` -- `https://kv-analytically.vault.azure.net/` (rg-analytically, uksouth) |
| Vault access model | **Access policy** (NOT RBAC -- admin lacks User Access Administrator). Grant with `az keyvault set-policy`. |
| Pipeline run identity | `admin@analytically.info` (oid `aafa257e-...`) -- dev **and** prod `Orchestrate_Build` run as this; already has get/list/set on the vault. |
| Notebook -> KV auth | `notebookutils.credentials.getToken("keyvault")` -- **confirmed works** on this Fabric. |

Key Vault secrets:
| Secret | Purpose | Status |
|---|---|---|
| `xero-client-id` | Xero app client id | seeded |
| `xero-client-secret` | Xero app secret | **you add** (step 1) |
| `xero-org-map` | `{"<xeroTenantId>": {"tenant_id": N, "default_site_id": "S"}}` | seeded `{}` |
| `xero-tokens` | `{"<connKey>": {"tokens": {...}, "tenants": [...]}}` -- per-consent | seeded `{}`, filled by onboarding |

---

## One-time setup (do once)

1. **Add the Xero app secret to the vault** (value from `API/xero_creds.local.py`):
   ```
   az keyvault secret set --vault-name kv-analytically --name xero-client-secret --value "<secret>"
   ```
2. **Import the notebooks** into the **prod** Fabric workspace: `Ingest_Xero` and the updated
   `Orchestrate_Build` (has the `run_xero_ingest` param + CELL 7b). (Repeat for dev if dev
   should pull the Demo org.)
3. **Deploy the site-resolution SQL** (once): `.\Scripts\Deploy.ps1 -Manifest Releases\V038__xero_site_resolution.manifest`
   (the earlier V034-V036 Xero medallion must already be deployed).

---

## Onboard a practice (per client)

1. **Consent** -- run locally, targeting the vault so the token lands where the notebook reads it:
   ```
   pip install azure-keyvault-secrets          # first time only
   set XERO_TOKEN_STORE=keyvault
   python API/xero_auth.py --key <clientName>  # opens browser; practice clicks Allow, picks their org
   ```
   Prints the connected org(s) + their Xero `tenantId` GUID(s).
2. **Map the org(s) to a Dentally tenant + site.** Read the current map, add the GUID, write it back:
   ```
   az keyvault secret show --vault-name kv-analytically --name xero-org-map --query value -o tsv
   # add "<xeroTenantId>": {"tenant_id": <N>, "default_site_id": "<SiteID>"} then:
   az keyvault secret set --vault-name kv-analytically --name xero-org-map --value '<full JSON>'
   ```
   (Xero's Demo Company auto-maps to Tenant_ID 99 with no entry.)
3. **Multi-site orgs (optional):** if one Xero org covers several sites split by a tracking
   category, add rows to `Config.Xero_Site_Map` (Tenant_ID, Category_Name, Option_Name, Site_ID).
   Otherwise every line falls back to `default_site_id`.

---

## Turn on / run the nightly pull

- In **prod** `Orchestrate_Build` parameters set `run_xero_ingest = True` (leave **False** in dev
  so dev never pulls real client data). `keyvault_url` defaults to the vault above.
- Run `Orchestrate_Build` once to test: CELL 7b lands `stage_xero_*`, then the DAG runs
  `BRONZE_XERO_* -> SILVER_XERO_* -> GOLD Fact_Finance` and refreshes the model.
- Reports (`_Finance` / Fact_Finance) update with the practice's cost/margin.

---

## Verify / troubleshoot

- **Refreshed N connection(s); tokens persisted** in the notebook output = KV read+write OK.
- **`kv_set` 401 / audience error** = the `getToken` audience is wrong for this Fabric; change
  the one line in `Ingest_Xero` `kv_set`/`kv_get` (try `"vault"` or `"https://vault.azure.net"`)
  and regenerate via `build_Ingest_Xero.py`.
- **"Skip unmapped org"** = that Xero `tenantId` isn't in `xero-org-map`; add it (step 2).
- **`fk_Practice_Site = -1` in Fact_Finance** = no site resolved; set the org's `default_site_id`
  in `xero-org-map`, or add `Config.Xero_Site_Map` rows.
- **Reconciliation:** summed `Fact_Finance` P&L should match Xero's own P&L report
  (validated to the penny on the Demo Company).

---

## Known follow-ups (not blockers)

- **Run the nightly pipeline under a service principal / workspace identity** instead of
  `admin@analytically.info` -- deliberate hardening for the WHOLE orchestration, not just Xero.
- **Incremental extraction** (`If-Modified-Since`) -- a cost optimisation once org-count grows;
  full snapshot pull is fine at single-practice volumes.
- **"Connect Xero" button** in the embed app tenant-admin, to replace the manual `xero_auth.py`
  consent for self-serve onboarding at scale.
