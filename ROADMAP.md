# Roadmap to SaaS-Ready

Tracked checklist derived from [EVALUATION.md](EVALUATION.md). Ordered by priority.
Check items off as they land; keep this file as the single source of truth for the hardening effort.

Status legend: `[ ]` todo &nbsp; `[~]` in progress &nbsp; `[x]` done

_Last refreshed: 2026-06-17._

---

## 1. Lock down multi-tenant security  _(Critical — gating for real tenants)_

- [x] Make embed RLS **mandatory and fail-closed** — `/api/embed-token` always attaches the RLS effective identity, 403s unprovisioned users, refuses if no role configured (commit 943985e, **live in prod**).
- [x] Drive RLS roles/identity from the user's actual tenant — embed-token verifies the caller maps to >=1 tenant via `Security.Application_Users` before issuing (same fix).
- [~] Verify token **issuer** — N/A as a simple pin: the app is **multi-tenant** (`authority=.../common`, users span analytically.info / mapledental.co.uk / outlook.com), so pinning one issuer would break legit sign-ins. Already mitigated by signature (Microsoft JWKS) + audience check + the `Application_Users` allowlist. Optional later: verify `iss` is consistent with the token's `tid`.
- [x] Remove the ROPC master-user password flow (`_pbi_delegated_token`, `PBI_PASSWORD`); SP-only — dead code removed (`USERNAME`/`PASSWORD`/`PBI_USERNAME` gone); embed + Fabric are SP-only. Also fixed the dead `rfgx` endpoint in `.env.example`.
- [x] Restrict CORS to known origins — `CORS(app, origins=[...])`, defaults to the app domains, `ALLOWED_ORIGINS` override (commit 6a19cd2, on dev).
- [x] Return generic error responses to clients; log detail server-side — all 6 `str(e)`/`_error` leaks masked via `_server_error()` (logs full detail via `app.logger`, returns generic message); embed upstream error no longer echoes `e.response.text`.
- [x] Run container as non-root (`Web/Dockerfile`); disable `debug=True` path — Dockerfile adds `appuser` (uid 10001) + `USER appuser`; Flask `debug` now env-gated (`FLASK_DEBUG`, default off).
- [x] Model-layer **RLS coverage guard** (`Scripts/Check_RLS_Coverage.ps1`, XMLA/ADOMD) — verifies the `RLS` role filters every tenant-bearing table; first run caught + closed 2 real leaks (`_NHS Claims`, `List NHS Contracts`); now green 29/29. **Wired into the `dw-tests` CI deploy gate** (ADOMD installed via NuGet, proven on the runner).
- [x] Behavioral **RLS isolation test** (`Scripts/Check_RLS_Isolation.ps1`, XMLA `EffectiveUserName`) — impersonates a user and proves every tenant-bearing table exposes only their tenant (+ sentinel). Verified: `admin@analytically.info` (T11) sees only T11 across all 29 tables with T12 data present. Closes off the blocked `executeQueries` path. **Now a third `dw-tests` CI gate** (proven on the runner; SP kept as workspace Admin).
- [x] Document the health-data compliance posture: encryption-at-rest, data-access auditing, retention/DSAR, backup/DR — `COMPLIANCE.md` (honest posture: in-place controls vs. TODOs; key gaps = data-access auditing, retention/DSAR policy, Key Vault for secrets, tested DR).

## 2. Database release engineering  _(Critical — unblocks everything else)_  — DONE

- [x] Adopt a migration tool — home-grown but complete: `Migrations/Vnnn__*.sql` (forward-only, idempotent ALTERs) applied by `Scripts/Migrate.ps1`, and the standard manifest runner `Scripts/Deploy.ps1` driving versioned `Releases/Vnnn__*.manifest` (tags `MIGRATE`/`DEPLOY`/`EXEC`/`TEST`). Piloted on the patient-cohort release.
- [x] Add a `schema_version` (migration state) table — `Migrate.Schema_Version` (version, checksum, applied-at, success), plus `Migrate.Deploy_Log` (per-deploy provenance: manifest, git commit SHA, branch, who, when, status) for audit + deterministic rollback.
- [x] Run migrations from CI against dev -> prod — `.github/workflows/deploy-warehouse.yml` runs a manifest via `Deploy.ps1` (as the SP) then the `dw-tests` gate. Deliberately `workflow_dispatch`-triggered (a controlled release, not an implicit push deploy) — by design, kept deliberate.
- [x] Retire the ~25 ad-hoc `Scripts/Deploy_*.ps1` scripts — all 24 bespoke/template/patch scripts + the two on-prem->Fabric bootstraps deleted (commits 130b588, 44e54d3). EVALUATION's "biggest maintainability risk" marked Resolved.
- [x] Service-principal auth + `Scripts/Run_Tests.ps1` harness (first step off manual interactive deploys)
- [ ] _Nicety:_ state-based diff (SqlPackage/DACPAC) to auto-generate migrations from `Fabric/*.Table.sql`, instead of hand-syncing the ALTER + the table definition.
- [ ] _Nicety:_ rollback policy is forward-only (roll-forward DROP-COLUMN migration); optional paired down-scripts not implemented (deliberately — avoids data-losing rollbacks).

## 3. Testing & CI gates  _(High)_

- [x] Wire `Scripts/Run_Tests.ps1` into CI as a pre-deploy gate (`.github/workflows/dw-tests.yml`; prod deploy `needs: dw-tests`). **Active and verified green in CI** (secrets `FABRIC_SP_*` added). Enforces reconcile/FK integrity + capture success **+ regression drift** — the latter now real after fixing the `Test.Capture_Baseline` DROP/CREATE bug (it was wiped on every deploy; commit a7a35e6) so the baseline survives redeploys.
- [x] Establish the first known-good baseline (`Test.usp_Promote`) — current baseline 122 metrics, **45 reconciles PASS / 120 OK / 2 OK(null)**, exit 0 (re-baselined after the patient-cohort feature added 5 cohort metrics).
- [ ] Add a post-deploy smoke test against the web app
- [ ] Add application tests (pytest) for `Web/app.py` auth + tenant-scoping helpers
- [ ] Add a minimal E2E check for the embed flow

## 4. Single source of truth for KPI logic  _(High)_

- [x] Delete the dead Flask KPI code: `/api/kpis`, all `_kpis_*`, `_wrap` + helpers in `Web/app.py` — ~400 lines removed (commit 28e5c40, on dev; preserved by tag `flask-kpi-cards-complete`)
- [ ] Confirm DAX (Tabular Editor scripts) is the sole KPI definition
- [ ] Reduce DAX duplication: generate the repetitive Target / vs-Target / BG colour measures data-driven

## 5. ETL refactor & incremental Gold  _(Medium — cost optimisation, NOT a scaling blocker)_

> Note: Fabric handles the volume fine — proven at ~1000 practices loading in
> seconds; throughput is a function of capacity, not the full-rebuild design. The
> driver here is **reducing CU consumption / cost**, so incrementals are worthwhile
> but not urgent. Full DROP/CREATE rebuilds are not a correctness or scale risk.

- [ ] Replace the ~60 hand-written blocks in `Audit.usp_Load_All` with a metadata-driven loop over `Process_Config` (maintainability) — **still todo** (the main remaining ETL item)
- [ ] Make `usp_Load_All` idempotent (CREATE OR ALTER / DROP+CREATE, not bare `ALTER PROCEDURE`); remove dead commented `EXEC`s; standardise on UTC timestamps — **still todo**
- [x] **Stable Gold surrogate keys** — effectively already stable: Gold dims/facts upsert (DELETE-orphan + hash-gated UPDATE + INSERT, keyed on bk + Tenant_ID); pks are preserved across reloads, never reassigned. No redesign needed.
- [~] **Incremental Gold load path** — substantially done: 5 of 6 transactional facts converted to watermark deltas (NHS Claims `V002`, Contracts + Treatment Plan Items `V004`, Invoice Items `V005`/`V006`, Payments `V007`). Patterns established: time-derived columns → live Gold `vw_` view (`V003`); sparse/derived flags → tiny positive table + LEFT JOIN in the view (`V005` discount, `V007` deposit). Remaining full-rebuild (cheap, acceptable): `Fact_Appointments` and the new `Fact_Appointment_Journey` (`V010`).

## 6. Operability / observability  _(Medium)_

- [ ] Structured logging + correlation IDs (replace `print()`)
- [ ] Error tracking (Sentry / App Insights) and alerting
- [ ] Health / readiness endpoint for Container Apps probes
- [ ] Reuse the MSAL `ConfidentialClientApplication` (token cache) and add DB connection pooling (`_fabric_conn` / `_pbi_token`)
- [ ] Deploy the immutable `:sha` image tag, not `:latest`, for deterministic rollback — **★ high value: stale `:latest` was the root cause of the 2026-06-15 prod outage** (security hardening removed an env var the old `:latest` image still required at boot; rebuilding `:latest` fixed it)

## 7. Documentation  _(Medium)_

- [x] EVALUATION.md (architecture critique)
- [x] ROADMAP.md (this file)
- [ ] README (what the product is, how to run it locally, how to deploy)
- [ ] Architecture overview (medallion layers, data flow, components)
- [ ] Runbook (deploys, common failures, recovery) — **★ rich material from 2026-06 to capture:** dev/prod are SEPARATE Fabric workspaces + warehouses; **keep the warehouse OUT of the Fabric deployment pipeline** (it copies object definitions only → empty tables + two sources of truth — manage the warehouse via the `Vxxx` SQL deploys); parameterise the semantic-model source (`pServer`/`pDatabase`) so every table repoints together (a named connection is invisible to the pipeline's parameter rule); the `:latest`-staleness outage + recovery
- [ ] Tenant-onboarding guide (currently manual `Security.Application_Users` + workspace setup)
- [ ] Data dictionary (Gold tables / PBI views)

## 8. SaaS-readiness  _(Medium)_

- [x] **Separate prod environment** — dev and prod are now distinct Fabric workspaces + warehouses (`…-4i26…` dev / `…-eljz…` prod); the prod Container App `FABRIC_SERVER` and the prod semantic model both point at the prod warehouse (parameterised source + deployment-pipeline parameter rule). (2026-06)
- [ ] Automate tenant provisioning (replace manual `Security.Application_Users` + `Security.Clients` + `Audit.Tenants` inserts + workspace/report/target setup) — **★ live now** (onboarding Maple Dental; real data targeted as Tenant 20). NB access-control tables are managed out-of-git per environment; secrets via a gitignored local `.sql`.
- [ ] Review cost/scale model (full Gold rebuilds, single capacity) as tenant count grows
