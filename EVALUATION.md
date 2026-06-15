# Solution Evaluation

_A complete, candid evaluation of the Dentally analytics platform as a base for a maintainable, robust SaaS product. Issues are tagged **[Critical] / [High] / [Medium] / [Low]** with specific file references._

_Authored 2026-06-13. This is a point-in-time review; verify against current code before acting._

---

## Overall verdict

This is a genuinely impressive solo-built analytics platform with a clean dimensional core and unusually disciplined naming. But it is **not yet a robust SaaS base** — the gap is concentrated in four areas: **database release engineering, security hardening, automated testing/CI gates, and documentation/operability**. The data modelling is the strong asset; the "productionisation" scaffolding around it is the weak one. None of the gaps are structural dead-ends; they are all addressable.

---

## What's genuinely good (keep / build on)

- **Medallion architecture is clean and consistent.** Bronze -> Silver -> Gold -> PBI with clear responsibilities, plus well-separated Audit / Meta / Config / Input / Security / Test schemas. Textbook and rare to see executed this consistently solo.
- **Naming conventions are excellent and enforced** (`pk_/bk_/fk_`, `usp_Load_*`, `DW_*`, acronym capitalisation). Onboarding into the SQL is easy because of this.
- **Metadata-driven ETL** (`Audit.Process_Config` + the dependency graph + `ETL_Run_Process`) is sophisticated — better orchestration than many commercial shops have.
- **Deterministic test data** (`generate_data.py`, seeded RNG, `uuid5`) is a strategic asset — it is what makes the whole regression-testing idea viable.
- **The regression / FK / KPI test framework** (`Test` schema) is the right instinct and well-designed: constituent-parts for ratios, baseline + reconcile split, exclusion of time-sensitive metrics.
- **Defensive Silver typing** (`TRY_CAST`), idempotent object scripts (DROP/CREATE), sentinel `-1` members — all correct dimensional practice.
- **Server-side tenant scoping** on the live custom endpoints (`_get_user_info` -> `Tenant_ID IN (...)`, parameterised) is done properly.
- **Sensible container** (`gunicorn`, msodbcsql18, slim base).

---

## [Critical] Security & multi-tenant data isolation

This is health data (dental records = UK GDPR **special-category** data). The bar is higher than generic SaaS, and several things need hardening **before** real tenants share the platform.

1. **ID-token issuer not verified.** `Web/app.py:56` sets `options={'verify_iss': False}` and pulls JWKS from the `/common/` endpoint. Audience is verified but not issuer/tenant — weakens the trust boundary. Pin issuer to your tenant.
2. **Embed RLS is optional and static.** In `/api/embed-token` (`Web/app.py:157`), the effective-identity `identities` block is only added **if `REPORT_ROLES` is non-empty**, and the roles are a single env-wide list applied to every user. If that env var is ever unset/misconfigured, the embed token grants View over the **entire multi-tenant dataset with no row filter**. Given an RLS mis-mapping has been hit before, this is the highest-risk line in the codebase. RLS should be **mandatory and fail-closed**, and driven by the user's actual tenant, not a static list.
3. **ROPC master-user password** (`PBI_PASSWORD`, `_pbi_delegated_token`) — deprecated, MFA-incompatible, and a plaintext credential in env. Eliminate in favour of SP-only.
4. **Wide-open CORS** (`CORS(app)`, `Web/app.py:15`) and **error detail leakage** (`return jsonify({'error': str(e)})` / `_error` across routes) — restrict origins, return generic errors to clients, log details server-side.
5. **Minor:** `debug=True` in `__main__` (`Web/app.py:814`); container runs as **root** (no `USER` in `Web/Dockerfile`).

**No visible compliance posture** for health data: no documented encryption-at-rest config, data-access auditing, retention / DSAR handling, or backup / DR policy (the `Gold_Backup` scripts are ad-hoc, not a DR plan). For a dental SaaS this is a **gating** concern, not a nice-to-have.

---

## [Resolved 2026-06-14] Database release engineering — was the biggest maintainability risk

**Status: addressed.** The original criticism (kept below) is resolved by the migration + manifest deployment system.

- **Migration/versioning system in place.** `Migrations/Vnnn__*.sql` (forward-only, idempotent ALTERs) applied by `Scripts/Migrate.ps1`, tracked in a **`Migrate.Schema_Version`** state table (version, checksum, applied-at, success) so what's applied where is recorded. Data-preserving by design (no DROP/CREATE of populated tables).
- **One standard runner replaces the ~25 bespoke scripts.** `Scripts/Deploy.ps1` applies a versioned, reviewable `Releases/Vnnn__*.manifest` of ordered, tagged actions (`MIGRATE`/`DEPLOY`/`EXEC`/`TEST`). The 24 one-off `Deploy_*.ps1`/`Patch_*.ps1` scripts have been **retired** (commit follows this edit); only the fresh-install bootstraps (`Deploy_To_Fabric.ps1`, `Migrate_Data_To_Fabric.ps1`) remain. The dead-`rfgx`-endpoint drift is gone with them.
- **Non-interactive + CI.** Everything authenticates as the Test Runner **service principal** (no MFA/one-person dependency). `.github/workflows/deploy-warehouse.yml` runs a manifest then the `dw-tests` gate; `Run_Tests.ps1` provides regression/reconcile/RLS gating. (Note: live prod object changes are driven by Fabric pipelines; these scripts are the dev/release path.)
- **Remaining nicety:** a state-based diff (SqlPackage/DACPAC) to auto-generate migrations from the target table definitions, instead of keeping `Fabric/*.Table.sql` and the `ALTER` migration in sync by hand.

<details><summary>Original criticism (now resolved)</summary>

- **There is no migration / versioning system for the warehouse.** Releases are ~25 hand-authored, accreting `Deploy_*.ps1` scripts (`Deploy_Gold_Only`, `Deploy_Fix_Recalls_SP`, `Deploy_KPI_Snapshot`, `Deploy_Fix_Journey_Issues`, ...). There is **no schema-migration state table**, so nothing records what has been applied to which environment. Proof: most of those scripts still point at the **dead `rfgx...` tenant endpoint** — they drift because there is no single source of truth.
- **DB deploys are fully manual and interactive** (one person's MFA). No CI, no reproducibility, high bus factor. (The service-principal + `Scripts/Run_Tests.ps1` work is the first step out of this.)
- **Recommendation:** adopt a real migration tool (Flyway / DbUp / sqlpackage-style) with versioned, ordered, idempotent migrations and a `schema_version` table, run from CI against dev -> prod. Retire the one-off scripts.

</details>

---

## [High] Data-engineering correctness & scale

- **Unstable Gold surrogate keys.** Gold is full DROP/CREATE and `pk_*` are regenerated each load (IDENTITY removed for Fabric, presumably `ROW_NUMBER`). Surrogate keys are therefore **not stable across loads** — fine while everything rebuilds together, but it blocks incremental fact loading, breaks any external key references, and is a latent correctness trap. At SaaS data volumes, **full Gold rebuilds will not scale** (cost + runtime grow with every tenant).
- **`Audit.usp_Load_All` is messy:** ~60 copy-pasted 5-line blocks; **every direct `EXEC` is commented out** (dead scaffolding alongside the live metadata dispatch — confusing); it is `ALTER PROCEDURE` (fails on a clean DB, unlike the DROP/CREATE used elsewhere); mixes `GETDATE()` / `SYSUTCDATETIME()`; and the header claims per-step isolation while the body just `THROW`s. Replace the hand-rolled list with a metadata-driven loop over `Process_Config` (the dependency graph already exists to order it).

---

## [High] Duplicated business logic & dead code

- **KPI logic exists twice:** in **DAX** (the Tabular Editor scripts) and in **Python** (`Web/app.py` `_wrap` + `_kpis_*`). Two implementations of the same metric definitions = guaranteed drift.
- **The Python KPI path is now dead.** `Web/index.html` no longer calls `/api/kpis` (it calls `/api/me`, `/api/filters`, `/api/embed-token`, `/api/targets` only). So ~250 lines of untested business logic in `app.py` (`/api/kpis`, all `_kpis_*`, `_wrap`) ship to prod but are never exercised. Delete it (the `flask-kpi-cards-complete` tag preserves it).
- **DAX duplication:** 40+ near-identical `Target` / `vs Target` / `BG` measures. The C# `add()` helper mitigates authoring, but the colour/band SWITCH logic is copy-pasted everywhere — a small data-driven generator would cut this dramatically.

---

## [High] Testing & CI gates

- **No application tests at all** — no pytest for the Flask backend, no frontend tests, no E2E. The new framework is **data-tier only**.
- **CI has no test gate.** `deploy-prod.yml` builds and ships on push to `main` with **zero tests run** — there is no quality gate between merge and production.
- The new regression framework is **manual and T11-only**, not wired into CI. The obvious next step (after the SP) is to run `Run_Tests.ps1` as a CI gate.

---

## [Medium] Operability / observability

- **Logging is `print()` to stdout** — no structured logging, no correlation IDs, no error tracking (Sentry / App Insights), no metrics, no alerting.
- **No health / readiness endpoint** in the Flask app for Container Apps probes.
- **Per-request inefficiency:** every request opens a **new pyodbc connection** and constructs a **new `ConfidentialClientApplication`** (`_fabric_conn` / `_pbi_token`), which **defeats MSAL's token cache** and adds an AAD round-trip per call. No connection pooling. This will bite under load.
- Deploys use the mutable `:latest` tag in `az containerapp update` (despite also pushing `:sha`), so rollbacks are not deterministic.

---

## [Medium] Documentation

- **The entire repo has one markdown file: `CLAUDE.md`** (plus this evaluation). No README, no architecture doc, no runbook, no data dictionary, no onboarding guide, no ADRs. For a product meant to be maintainable by more than one person, this is a serious gap — system knowledge currently lives in one person's head. The strong naming conventions partially compensate, but a new engineer (or future-you) has no map.

---

## [Medium] SaaS-readiness gaps

- **Tenant onboarding is manual** (hand-inserted `Security.Application_Users` rows, workspace / report setup, target seeding). No provisioning automation or self-serve — every new customer is bespoke work.
- **Isolation is logical (RLS), not physical** — acceptable, but it puts all the weight on the RLS correctness flagged above being bulletproof.
- **Cost model scales poorly** (full Gold rebuilds, single capacity) as tenant count grows.

---

## Prioritised roadmap (recommended order)

1. **Lock down multi-tenant security**: mandatory fail-closed RLS, verify issuer, kill ROPC, restrict CORS, generic error responses. _(Gating for real tenants.)_
2. **Introduce DB migrations + a `schema_version` table**, run from CI; retire the ad-hoc deploy scripts. _(Unblocks everything else.)_
3. **Wire `Run_Tests.ps1` (SP auth) into CI as a deploy gate**; add a smoke test on the web app post-deploy.
4. **Delete the dead Flask KPI code**; make DAX the single KPI source of truth.
5. **Refactor `usp_Load_All`** to metadata-driven; design stable Gold surrogate keys + an incremental path before data volumes grow.
6. **Add baseline observability** (structured logs + error tracking + health endpoint) and fix per-request token / connection reuse.
7. **Write the docs**: README, architecture overview, runbook, tenant-onboarding guide, data dictionary; document the compliance / DR posture for health data.
