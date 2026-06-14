# Data protection & compliance posture

Working document for the Analytically platform (multi-tenant dental-practice
analytics). It records the **current** controls and the **gaps** still to close.
It is a posture statement, not a certification. Where a control is not yet in
place it is marked **TODO** rather than overstated.

## Data classification

- The warehouse holds **special-category personal data** (patient health/clinical
  and financial records) under UK GDPR. Treat all tenant data as confidential and
  tenant-isolated.
- Data is **partitioned by tenant** (`Tenant_ID`) end to end (Bronze -> Gold ->
  PBI), and every analytics surface is row-level-security scoped to the signed-in
  user's tenant(s).

## Access control & isolation  _(in place)_

- **Authentication:** Entra ID (Azure AD). The web app validates the caller's ID
  token (Microsoft JWKS signature + audience check) on every protected route.
- **Authorisation:** a caller must be a provisioned `Security.Application_Users`
  row mapped to >= 1 tenant, or the request is refused (403).
- **Row-level security:** the Power BI `RLS` role is **mandatory and fail-closed** —
  `/api/embed-token` always attaches the RLS effective identity and refuses to mint
  a token if the role is unconfigured or the user maps to no tenant. Verified by two
  CI gates: `Check_RLS_Coverage.ps1` (every tenant-bearing table is filtered) and
  `Check_RLS_Isolation.ps1` (a user sees only their tenant).
- **Service identity:** server-to-Fabric/PBI calls use a service principal
  (client-credentials), not stored user passwords. The legacy ROPC
  username/password flow has been **removed**.
- **CORS** is restricted to the app's own origins.
- **Transport:** HTTPS at the edge (Container Apps); SQL connections use
  `Encrypt=True`; PBI/Fabric APIs are TLS.

## Encryption at rest  _(provider-managed)_

- **Microsoft Fabric / OneLake** encrypts all data at rest with Microsoft-managed
  keys (Azure Storage service-side encryption). No customer-managed key (CMK) is
  configured. **TODO:** decide whether CMK / Bring-Your-Own-Key is required for the
  compliance bar, and document key rotation.
- **Secrets** (SP client secret, etc.) are held as platform secrets (GitHub Actions
  secrets for CI; Container Apps secrets / env for runtime) and the local
  `Scripts/fabric_creds.local.ps1` is gitignored. **TODO:** move runtime secrets to
  Azure Key Vault with managed-identity access instead of plain env vars.

## Auditing  _(partial)_

- **ETL audit:** the `Audit` schema logs pipeline execution (runs, record counts,
  errors) with UUID tracking.
- **Deploy audit:** `Migrate.Schema_Version` + `Migrate.Deploy_Log` record every
  schema/release change (git SHA, who, when, status).
- **TODO — data-access auditing:** there is no per-query / per-user *read* audit of
  who viewed which tenant's data. Evaluate Fabric/PBI activity logs + Entra sign-in
  logs and define a retention period for them.

## Retention, DSAR & erasure  _(TODO)_

- No formal data-retention schedule or automated **DSAR / right-to-erasure**
  workflow exists yet. Source of record is the upstream Dentally system; the
  warehouse is a downstream copy.
- **TODO:** define retention per data class; define how an erasure/SAR request
  propagates to (or is satisfied from) the warehouse; document the lawful basis and
  the data-processor relationship with each practice (tenant) as controller.

## Backup & disaster recovery  _(partial)_

- Fabric/OneLake provides platform-level durability and redundancy for stored data;
  source data is re-ingestible from the Dentally API, and Gold is rebuildable from
  Bronze/Silver via the load procedures.
- Test-data save/restore exists (`Scripts/Backup_Test_Data.ps1` /
  `Restore_Test_Data.ps1`).
- **TODO:** document the RPO/RTO targets, the production restore procedure, and test
  a restore. Confirm Fabric backup/point-in-time options for the warehouse.

## Container / runtime hardening  _(in place / partial)_

- The web container runs as a **non-root** user; Flask `debug` is **off** by default
  (only enabled via `FLASK_DEBUG`); error responses to clients are **generic** with
  detail logged server-side only.
- **TODO:** deploy the immutable `:sha` image tag (not `:latest`) for deterministic
  rollback; add a health/readiness probe; structured logging + error tracking
  (see ROADMAP sections 6).

## Open items (tracked in ROADMAP.md)

The TODOs above are the compliance-relevant slice of the hardening roadmap. The
near-term priorities are: data-access auditing, a retention/DSAR policy, Key Vault
for runtime secrets, and a documented + tested DR procedure.
