# Roadmap to SaaS-Ready

Tracked checklist derived from [EVALUATION.md](EVALUATION.md). Ordered by priority.
Check items off as they land; keep this file as the single source of truth for the hardening effort.

Status legend: `[ ]` todo &nbsp; `[~]` in progress &nbsp; `[x]` done

---

## 1. Lock down multi-tenant security  _(Critical — gating for real tenants)_

- [ ] Make embed RLS **mandatory and fail-closed** — never issue an embed token without a tenant-scoped effective identity (`Web/app.py:157`)
- [ ] Drive RLS roles/identity from the user's actual tenant, not the static `REPORT_ROLES` env list
- [ ] Verify token **issuer** (pin to tenant) instead of `verify_iss: False` (`Web/app.py:56`)
- [ ] Remove the ROPC master-user password flow (`_pbi_delegated_token`, `PBI_PASSWORD`); SP-only
- [ ] Restrict CORS to known origins (`Web/app.py:15`)
- [ ] Return generic error responses to clients; log detail server-side (remove `str(e)` / `_error` leakage)
- [ ] Run container as non-root (`Web/Dockerfile`); disable `debug=True` path (`Web/app.py:814`)
- [ ] Document the health-data compliance posture: encryption-at-rest, data-access auditing, retention/DSAR, backup/DR

## 2. Database release engineering  _(Critical — unblocks everything else)_

- [ ] Adopt a migration tool (Flyway / DbUp / sqlpackage-style) with versioned, ordered, idempotent migrations
- [ ] Add a `schema_version` (migration state) table so applied state is known per environment
- [ ] Run migrations from CI against dev -> prod
- [ ] Retire the ~25 ad-hoc `Scripts/Deploy_*.ps1` scripts once migrations replace them
- [x] Service-principal auth + `Scripts/Run_Tests.ps1` harness (first step off manual interactive deploys)

## 3. Testing & CI gates  _(High)_

- [x] Wire `Scripts/Run_Tests.ps1` into CI as a pre-deploy gate (`.github/workflows/dw-tests.yml`; prod deploy `needs: dw-tests`). **Activate by adding repo secrets `FABRIC_SP_TENANT` / `FABRIC_SP_CLIENT_ID` / `FABRIC_SP_CLIENT_SECRET`.** Enforces reconcile/FK integrity + capture success; regression-drift gate awaits a persisted baseline.
- [x] Establish the first known-good baseline (`Test.usp_Promote`) — `baseline-v2`, 45 reconciles PASS / 115 OK / 2 OK(null), exit 0
- [ ] Add a post-deploy smoke test against the web app
- [ ] Add application tests (pytest) for `Web/app.py` auth + tenant-scoping helpers
- [ ] Add a minimal E2E check for the embed flow

## 4. Single source of truth for KPI logic  _(High)_

- [ ] Delete the dead Flask KPI code: `/api/kpis`, all `_kpis_*`, `_wrap` in `Web/app.py` (preserved by tag `flask-kpi-cards-complete`)
- [ ] Confirm DAX (Tabular Editor scripts) is the sole KPI definition
- [ ] Reduce DAX duplication: generate the repetitive Target / vs-Target / BG colour measures data-driven

## 5. ETL refactor & Gold scalability  _(High)_

- [ ] Replace the ~60 hand-written blocks in `Audit.usp_Load_All` with a metadata-driven loop over `Process_Config`
- [ ] Make `usp_Load_All` idempotent (CREATE OR ALTER / DROP+CREATE, not bare `ALTER PROCEDURE`); remove dead commented `EXEC`s; standardise on UTC timestamps
- [ ] Design **stable Gold surrogate keys** (survive reloads) to enable incremental fact loading
- [ ] Add an incremental Gold load path; stop full DROP/CREATE rebuilds before data volumes grow

## 6. Operability / observability  _(Medium)_

- [ ] Structured logging + correlation IDs (replace `print()`)
- [ ] Error tracking (Sentry / App Insights) and alerting
- [ ] Health / readiness endpoint for Container Apps probes
- [ ] Reuse the MSAL `ConfidentialClientApplication` (token cache) and add DB connection pooling (`_fabric_conn` / `_pbi_token`)
- [ ] Deploy the immutable `:sha` image tag, not `:latest`, for deterministic rollback

## 7. Documentation  _(Medium)_

- [x] EVALUATION.md (architecture critique)
- [x] ROADMAP.md (this file)
- [ ] README (what the product is, how to run it locally, how to deploy)
- [ ] Architecture overview (medallion layers, data flow, components)
- [ ] Runbook (deploys, common failures, recovery)
- [ ] Tenant-onboarding guide (currently manual `Security.Application_Users` + workspace setup)
- [ ] Data dictionary (Gold tables / PBI views)

## 8. SaaS-readiness  _(Medium)_

- [ ] Automate tenant provisioning (replace manual `Security.Application_Users` inserts + workspace/report/target setup)
- [ ] Review cost/scale model (full Gold rebuilds, single capacity) as tenant count grows
