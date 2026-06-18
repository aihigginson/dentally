# Access Model — Analytically

How identities, accounts and service principals are separated so that access to
customer/production data is **least-privilege, exceptional, MFA-protected and
auditable**. This is the operational control behind DPIA §4. Current org size:
**one developer-administrator** — the model is written to scale, but described
honestly for a single-person company.

---

## 1. Target identity model

| Identity | Can access | MFA | Purpose |
|---|---|---|---|
| **Dev account** (`dev@…`) | Dev workspace + dev warehouse (synthetic data) **only** | **Off** (exempt) | Day-to-day development + deploys to dev. No production, no real data, so repeated re-auth is unnecessary friction. |
| **Prod-admin account** (`admin@…`) | Prod workspace + prod warehouse | **Enforced** | Support, incident investigation, maintenance — **only when required**, time-limited, logged. Not used for routine work. |
| **Report-viewer account** (`viewer@…`) | Front-end embedded reports **only** (a normal tenant user); **no** database / workspace access | Enforced (it can see a tenant's data) | Checking report layouts / UX without touching the warehouse. Map it to a demo/synthetic tenant. |
| **Dev service principal** | Dev warehouse (DDL+DML for deploy/tests) | n/a (secret) | Used by `Deploy.ps1` / `Run_Tests.ps1` locally. Secret lives in `Scripts/fabric_creds.local.ps1` (gitignored). |
| **Prod service principal** | Prod warehouse (DDL+DML for deploy) | n/a (secret) | Used **only** for prod deploys, from CI or an on-demand elevated session. Secret stored in the CI secret store / a separate gitignored prod creds file — **not** in the routine local path. |

**Principle:** the only identity used day-to-day (dev account + dev SP) cannot reach
production or real patient data. Reaching production is a deliberate, separate,
MFA-protected step.

---

## 2. Entra groups + Conditional Access

1. Create three groups: `analytically-dev`, `analytically-prod-admin`, `analytically-viewers`.
2. **Conditional Access policy:** require MFA for `analytically-prod-admin` (and any
   account with prod-DB access). Excluding the dev account from MFA is acceptable
   **only because** it has no production or real-data access — document that as the
   compensating control.
3. Keep the dev account out of `analytically-prod-admin`. If you need to do prod work,
   sign in as the prod-admin account (MFA), do the task, sign out — don't merge the roles.

---

## 3. Fabric workspace roles

- Dev account → **Member/Contributor** on the **dev** workspace only.
- Prod-admin account → **Member/Admin** on the **prod** workspace (used on demand).
- Viewer account → **Viewer** on the published app / report only; **no** workspace or
  SQL-endpoint role (so it cannot query the warehouse directly).
- Dev SP → added to the **dev** workspace; Prod SP → added to the **prod** workspace.
  (RLS does **not** apply to direct SP queries — that is exactly why the SPs are split
  and the prod secret is kept out of the routine local path.)

---

## 4. Service-principal split + Test Runner tightening

Today a single "Test Runner" SP is a member of **both** workspaces and its secret sits in
the local creds file — meaning the everyday local environment can query **prod** directly.
Tighten as follows:

1. **Register two app registrations** (or two SPs): `analytically-deploy-dev` and
   `analytically-deploy-prod`.
2. Grant each to **only** its own workspace/warehouse.
3. **Local** `Scripts/fabric_creds.local.ps1` holds **only the dev SP** secret. Deploys to
   dev "just work"; deploys to prod require the prod SP secret, which you supply
   deliberately (env var for the session, or CI).
4. **CI:** store the prod SP secret as a GitHub Actions secret; the prod deploy workflow
   reads it. The dev SP secret stays for dev CI.
5. **Least privilege:** the deploy SPs need DDL+DML on the warehouse (to run migrations and
   the test framework) — scope them to the warehouse role they need, nothing broader
   (no tenant admin, no capacity admin).
6. Retire the combined "Test Runner" SP once both replacements are in place.

**Resulting DPIA statement:** *"Development activity uses a dev-only identity restricted to
a synthetic-data environment. Production access is separated, granted only when required,
MFA-protected, time-limited and logged. Administrative access is not used for routine
development."*

---

## 5. Audit logging (supporting control)

- Enable + retain **Entra sign-in logs** and **Fabric/Power BI activity logs** (these
  capture admin sign-ins and report/query activity). Define a retention period
  (e.g. 12 months) — **[DECISION NEEDED]**.
- Warehouse ETL + deploys are already audited (`Audit` schema, `Migrate.Deploy_Log`).

---

## 6. What is code vs what you do

- **You (Entra/Fabric/Azure portal):** create the accounts + groups, the Conditional Access
  policy, the two app registrations, and assign workspace roles. These cannot be created
  from this repo.
- **In the repo (done / to do):** keep the prod SP secret out of `fabric_creds.local.ps1`;
  wire the prod SP secret into the prod deploy workflow; point `Deploy.ps1` at the dev SP by
  default. Tracked alongside the V012/V013 work.
