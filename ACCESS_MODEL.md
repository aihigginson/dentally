# Access Model — Analytically

How identities, accounts and service principals are separated so that access to
customer/production data is **least-privilege, exceptional, MFA-protected and
auditable**. This is the operational control behind DPIA §4. Current org size:
**one developer-administrator** — the model is written to scale, but described
honestly for a single-person company.

> **Status — 2026-06-18:** human accounts + groups **created and live**; per-user
> MFA enforced on `dev@` / `ops@` / `viewer@`; `Admin@` deliberately MFA-exempt as
> the break-glass account. Dev/ops have their Fabric workspace roles. Viewer pending
> its app access-table entry. **Service-principal split (§4) complete** — dev SP
> (secret, dev-only) + prod SP (OIDC, no stored secret) both tested green; old
> Test Runner SP workspace access revoked (delete the app registration when confident).

---

## 1. Identity model (as built)

| Identity | Access | MFA | Status |
|---|---|---|---|
| **`Admin@analytically.info`** | Global Admin (everything) | **Off — break-glass** | Untouched; the guaranteed way in. Excluded from all MFA enforcement. |
| **`dev@analytically.info`** | Dev workspace (Contributor), synthetic data only | **On** (Authenticator / passkey) | ✅ created, MFA enforced, workspace access confirmed |
| **`ops@analytically.info`** | via `Analytically-Prod-Admin` group: prod ws (Admin) + dev ws (Member, read/release) + DEV->PROD deployment pipeline (Admin) — the **release identity** | **On** (Authenticator / passkey) | ✅ created, MFA enforced |
| **`viewer@analytically.info`** | Embedded app reports only; **no** DB/workspace | **On** | ✅ created; **pending** `Security.Application_Users` entry → demo tenant before it can see anything |
| **`analytically-deploy-dev` SP** | Dev workspace (Admin) | n/a (client secret — local creds + dev CI) | ✅ created + tested green |
| **`analytically-deploy-prod` SP** | Prod workspace (Admin) | n/a (**GitHub OIDC**, no stored secret) | ✅ created + tested green |
| **`Dentally DW Test Runner` (old)** | — (access revoked) | — | ⛔ retired: workspace access removed; delete app registration when confident |

**Principle:** the only identity used day-to-day (`dev@` + the dev SP) cannot reach
production or real patient data. Reaching production is a deliberate, separate,
MFA-protected step.

---

## 2. Groups + MFA enforcement (as built)

- Three security groups created: **`Analytically-Dev`**, **`Analytically-Prod-Admin`**,
  **`Analytically-Viewers`** (access is assigned to the *group*, not the user, so future
  accounts inherit it).
- **MFA: free per-user MFA**, not Conditional Access. Conditional Access (the
  best-practice route, with report-only dry-runs) needs **Entra ID P1**, which this tenant
  doesn't have spare; per-user MFA achieves the same outcome at no cost and per-account.
  `dev@`/`ops@`/`viewer@` set to **Enabled**; `Admin@` left **Disabled** (break-glass).
- **Future upgrade:** if Entra ID P1 becomes available, migrate to a Conditional Access
  policy (require MFA for the three groups, **exclude `Admin@`**, roll out in report-only
  first), and retire per-user MFA.

---

## 3. Fabric workspace roles (as built)

- `Analytically-Dev` → **Contributor** on the **dev** workspace. ✅
- `Analytically-Prod-Admin` → **Admin** on the **prod** workspace (used on demand). ✅
- `Analytically-Viewers` → **no** workspace/SQL role (reaches reports only through the
  embedded app, gated by `Security.Application_Users`). ✅
- Dev SP → dev workspace; Prod SP → prod workspace (⏳ §4).

**Licensing note:** opening a Fabric workspace needs a licence. `dev@` auto-started a
**60-day Power BI Pro trial** (expires ~mid-Aug 2026). Before it lapses, assign the
**minimum permanent licence** — **Fabric (Free)** if warehouse/Fabric-item work suffices,
**Power BI Pro** only if PBI report *authoring* in the workspace is needed. Don't buy
speculatively.

---

## 4. Service-principal split + OIDC (done — 2026-06-18)

Today a single "Test Runner" SP is a member of **both** workspaces and its secret sits in
the local creds file — so the everyday local environment can query **prod** directly.
Target:

1. **Two app registrations:** `analytically-deploy-dev`, `analytically-deploy-prod`,
   each added to the tenant's Fabric SP-access group and to **only** its own workspace.
2. **Dev SP:** client secret in `Scripts/fabric_creds.local.ps1` (gitignored) — local +
   dev CI. Deploys to dev "just work".
3. **Prod SP:** **GitHub OIDC federated credential — no stored secret.** Prod warehouse
   deploys run in CI (`deploy-warehouse`), where GitHub Actions exchanges an OIDC token
   for the prod SP; nothing prod-capable lives on a laptop.
4. **Least privilege:** the deploy SPs get only the warehouse DDL+DML role they need — no
   tenant/capacity admin.
5. **Retire the combined "Test Runner" SP** once both replacements are proven (kept as a
   live fallback until then, so a half-finished split can't break a prod deploy).

**Resulting DPIA statement:** *"Development uses a dev-only identity restricted to a
synthetic-data environment. Production access is separated, exceptional, MFA-protected
(humans) / federated-token (automation), and audited. Administrative access is not used
for routine development."*

---

## 4b. Promotion (dev -> prod) — who deploys what

| What | Promotion path | Run as |
|---|---|---|
| **Warehouse** (tables/procs/views + data reloads) | Git manifest -> `Deploy.ps1` (dev) / **Deploy Warehouse** Action (prod, OIDC) | automation (SPs) |
| **Reports, semantic model, notebooks, lakehouse** | the **Fabric deployment pipeline** "DEV TO PROD" | `ops@` (release identity) |

- **Do not deploy the warehouse (`DM Dentally`) through the Fabric deployment pipeline** — untick it on Deploy. It only syncs schema (no migrations, no data reload, no regression gate); the Git manifest path does all three and is the source of truth.
- **Semantic-model data-source connection:** after a deployment-pipeline promotion the prod semantic model's data source must be **bound** to a connection to the prod warehouse, and that **connection must be shared with `Analytically-Prod-Admin`** (connections have their own access list, separate from workspace roles) — otherwise the release operator gets "missing connection details / disconnected". **DONE 2026-06-19:** the connection now authenticates as the **app service principal `ea34f12f`** (Service Principal auth, not a person's OAuth), shared with `Analytically-Prod-Admin`; prod refresh verified green. No longer tied to an individual. **Coupling to note:** the SP's client secret now also lives in this Fabric connection, so rotating `ea34f12f`'s secret means updating **both** the Container App config **and** this connection.
- **`ops@` is the release identity** — access granted via the **`Analytically-Prod-Admin` group** (consistent with the group-based model, not direct-to-user): the group is **Member** on the **dev** workspace (read the source stage), **Admin** on **prod**, and **Admin** on the DEV->PROD deployment pipeline. This lets a single operator build as `dev@` and promote as `ops@` without the `Admin@` break-glass. Reading dev (synthetic data) is an accepted, low-risk loosening.

---

## 5. Audit logging (supporting control)

- Enable + retain **Entra sign-in logs** and **Fabric/Power BI activity logs**. Define a
  retention period (e.g. 12 months) — **[DECISION NEEDED]**.
- Warehouse ETL + deploys are already audited (`Audit` schema, `Migrate.Deploy_Log`).

---

## 6. Code vs portal

- **You (Entra/Fabric portal):** ✅ accounts, groups, per-user MFA, workspace roles done;
  ⏳ create the two app registrations + their workspace/SP-group membership + the prod SP's
  GitHub federated credential.
- **In the repo (I do):** split `fabric_creds.local.ps1` to dev-only; teach `Deploy.ps1` to
  accept an OIDC-acquired token; wire the prod SP + OIDC into the warehouse deploy workflow;
  point local defaults at the dev SP.
