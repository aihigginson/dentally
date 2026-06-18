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
- [x] Add a post-deploy smoke test against the web app — `deploy-dev.yml` + `deploy-prod.yml` now curl `/health` (6× retry) after the Container App update and fail the deploy if it's not 200.
- [x] Add application tests (pytest) for `Web/app.py` auth + tenant-scoping helpers — `Web/tests/` (16 tests): `_auth` (token→upn, expiry, missing/no-upn), `_get_user_info` (UPN→client/tenants), and the **fail-closed embed token** (401 unauth, 404 unknown report, 500 if RLS roles empty, 403 unprovisioned, 200 happy path), + `/api/me` & `/api/targets` 403-when-unprovisioned. Run in CI via `app-tests.yml`.
- [ ] Add a minimal E2E check for the embed flow — *(still todo; needs a live auth'd browser session — heavier than the unit + smoke layers above)*

## 4. Single source of truth for KPI logic  _(High)_

- [x] Delete the dead Flask KPI code: `/api/kpis`, all `_kpis_*`, `_wrap` + helpers in `Web/app.py` — ~400 lines removed (commit 28e5c40, on dev; preserved by tag `flask-kpi-cards-complete`)
- [x] Confirm DAX (Tabular Editor scripts) is the sole KPI definition — verified: no KPI computation remains in `Web/app.py` (routes are `/`, `/health`, auth-config, embed-token, me, filters, targets); dead Flask KPI code already removed (commit 28e5c40)
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

- [x] Structured logging + correlation IDs (replace `print()`) — all `print()` replaced with `app.logger`; a per-request correlation id (`X-Request-ID`, honoured if inbound else minted) is injected into every log line via a logging filter and echoed back in the response header for client↔server tracing.
- [ ] Error tracking (Sentry / App Insights) and alerting — *(needs the Sentry/App Insights resource + DSN created first; then a gated init hook)*
- [~] Health / readiness endpoint for Container Apps probes — `/health` **live + verified on dev** (200 `{status:ok}`, unauthenticated, no deps). Remaining: wire the Container App liveness/readiness probe to it (via `az`/workflow).
- [~] Reuse the MSAL `ConfidentialClientApplication` (token cache) and add DB connection pooling — **MSAL done**: `_pbi_msal`/`_fabric_msal` are now reused lazy singletons (in-memory token cache; previously rebuilt on every call, so AAD was hit per request). DB connection pooling **deferred** — token-auth connections (token in `attrs_before`, not the conn string) don't pool cleanly, so connect-per-request is kept deliberately.
- [x] Deploy the immutable `:sha` image tag, not `:latest`, for deterministic rollback — both `deploy-dev.yml` + `deploy-prod.yml` now build **and deploy `:${{ github.sha }}`** (the mutable `:dev`/`:latest` tags are still built as "newest" pointers). Each revision is pinned to an exact build; rollback = redeploy a prior commit's sha. Directly fixes the stale-`:latest` failure mode behind the 2026-06-15 outage.

## 7. Documentation  _(Medium)_

- [x] EVALUATION.md (architecture critique)
- [x] ROADMAP.md (this file)
- [x] README (what the product is, how to run it locally, how to deploy) — `README.md`
- [x] Architecture overview (medallion layers, data flow, components) — covered in `README.md` (Architecture section) + `CLAUDE.md`
- [x] Runbook — `RUNBOOK.md`: environments, deploy procedures (web/warehouse/PBI + rollback), the golden rules, incident playbook (A–E for the failures actually hit), diagnostics, and the access-control model. Captures the 2026-06 learnings (dev/prod warehouse split, warehouse-out-of-pipeline, parameterised source, the `:latest` outage).
- [x] Tenant-onboarding guide — `TENANT_ONBOARDING.md` (the manual `Audit.Tenants` + `Security.Clients`/`Application_Users` chain, data load, RLS verification, gotchas)
- [ ] Data dictionary (Gold tables / PBI views)

## 8. SaaS-readiness  _(Medium)_

- [x] **Separate prod environment** — dev and prod are now distinct Fabric workspaces + warehouses (`…-4i26…` dev / `…-eljz…` prod); the prod Container App `FABRIC_SERVER` and the prod semantic model both point at the prod warehouse (parameterised source + deployment-pipeline parameter rule). (2026-06)
- [ ] Automate tenant provisioning (replace manual `Security.Application_Users` + `Security.Clients` + `Audit.Tenants` inserts + workspace/report/target setup) — **★ live now** (onboarding Maple Dental; real data targeted as Tenant 20). NB access-control tables are managed out-of-git per environment; secrets via a gitignored local `.sql`.
- [ ] Review cost/scale model (full Gold rebuilds, single capacity) as tenant count grows
