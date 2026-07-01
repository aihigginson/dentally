# Xero Integration — plan

Purpose: extract each practice's **Xero** accounting data and merge it into the Dentally
model so practices get **profitability** — cost and margin sitting alongside the revenue we
already hold from Dentally. Multi-tenant: every practice authorises their own Xero
organisation.

_Status: PLANNING (2026-07-01). No code yet. This doc is for sign-off before build._

---

## 1. Objective & scope

- **What it adds:** the model already has the *revenue* side from Dentally
  (`Gold.Fact_Invoices`, `Gold.Fact_Payments`, `Gold.Dim_Accounts`). Xero holds what Dentally
  does **not** — chart of accounts, bills/expenses, bank transactions and the true P&L — i.e.
  the **cost** side. Together they give **profit & margin per practice**.
- **Tenancy:** multi-tenant. Each practice connects their **own** Xero org via OAuth2.
- **Primary goal:** profitability (costs vs revenue). Full statutory reporting is out of scope
  for v1.

## 2. The grain & join reality (read this first)

Xero does **not** join at patient or appointment grain. It joins at
**Practice-Site × Period × GL-account**. The merge is aggregate financial: Xero costs/P&L next
to Dentally revenue by site and period. (Same reality we hit with GA — there is no natural
person-level key.)

- **Source of truth = Xero `Journals`** — the immutable general ledger. Every invoice, bill,
  bank transaction and manual journal appears here as balanced double-entry lines, each with
  an account, amount, date and (optionally) tracking category. Modelling on Journals means one
  consistent grain instead of stitching many document types.
- `Accounts` gives the **chart of accounts** (type/class → revenue/expense/overhead).
- `TrackingCategories` gives the **site split** when one org spans multiple locations.
- The `Reports/ProfitAndLoss` endpoint is used **only as a reconciliation check**, not as the
  primary feed (it is pre-aggregated and awkward to model dimensionally).

## 3. How it slots into the medallion (existing pattern)

Xero is just a new **source**, following the same path every source already uses:

1. **Extractor** (Python) → raw records as Delta to OneLake `Tables/dbo/stage_xero_*`
   (mirrors `API/seed_onelake.py`, but a real API client instead of the mock generator).
2. **Bronze** — Stage views over the Delta tables, read by `Bronze.usp_Load_Xero_*`
   (raw strings, `TRY_CAST`, MERGE, per-tenant, Audit ETL logging).
3. **Silver** — typing + business logic: org/tracking → **Practice-Site** mapping, and account
   **classification**.
4. **Gold** — `Dim_GL_Account` + `Fact_Finance` (journal-line grain), surrogate `fk_*` keys
   joined on `Dim_Practice_Sites`, `Dim_Date`, `Dim_Tenants`.
5. **PBI views + orchestration** — `Meta.usp_Create_Gold_Views`, `Audit.Process_Config` +
   `Audit.Process_Dependency`, the nightly Fabric pipeline, manifest deploy.

## 4. Data model (Gold)

- **`Gold.Dim_GL_Account`** — one row per (tenant, Xero account): code, name, **type**, **class**
  (Revenue / Direct Cost / Expense / Overhead / Asset / Liability), plus the **standard cost
  taxonomy** mapping (see §7).
- **`Gold.Fact_Finance`** — one row per **journal line**: `fk_Tenant`, `fk_Practice_Site`,
  `fk_Date`, `fk_GL_Account`, signed `Amount`, source document type/ref. Aggregates cleanly to
  site × period × account, and to the P&L classes for margin.
- **Reconciliation view** — Xero revenue accounts vs Dentally `Fact_Invoices` by site/period, so
  divergence (timing, scope, out-of-Dentally income) is visible rather than silent.
- **PBI measures** — Revenue (Dentally) − Direct Cost − Overhead = Gross/Net margin; cost ratios;
  margin per site / per period.

## 5. Recommended sequencing — split the two hard problems

There are two independent sources of difficulty; bolting them together is how these stall.

1. **The data model & join** — Journals → `Fact_Finance` → margin vs Dentally revenue.
2. **The multi-tenant OAuth machinery** — per-practice consent, rotating token store, scale.

**Build #1 first as a vertical slice on ONE org** (Xero's free **Demo Company**, or one org with
a hand-made token), prove the profitability model and the site × period join end-to-end, **then**
build the multi-tenant onboarding around a model we already trust.

## 6. Phased plan

### Phase 0 — Foundations
- Register a Xero app at developer.xero.com. Scopes: `accounting.reports.read`,
  `accounting.transactions.read`, `accounting.settings.read`, `accounting.journals.read`,
  `offline_access`.
- Compliance groundwork: per-practice financials are **Controller data** → Xero is a **new
  sub-processor**. Draft `SUB_PROCESSOR_REGISTER.md` / DPA / DPIA updates.

### Phase 1 — Vertical slice (one org, model-first)  ← start here
- Extractor for `Journals`, `Accounts`, `TrackingCategories` → OneLake `stage_xero_*`.
- Bronze → Silver → `Dim_GL_Account` + `Fact_Finance`.
- Join to the model + one **margin** measure + the **reconciliation view**.
- Validate on Xero's **Demo Company** (no card, no real data).

### Phase 2 — Multi-tenant OAuth
- "Connect Xero" flow in the embed app's tenant-admin area (`app.analytically.info`).
- **Per-tenant refresh-token store in Key Vault.** Xero **rotates** refresh tokens on every use —
  persist the new one each time; refresh token expires after 60 days of inactivity; access token
  lasts 30 min.
- Xero-org → Practice-Site **mapping table** + onboarding step.

### Phase 3 — Productionise
- Nightly, rate-limit-aware extraction (see §8), staggered per org.
- `Process_Config` / `Process_Dependency` rows; Fabric pipeline; manifest release.
- Finalise compliance artifacts.

## 7. Chart-of-accounts standardisation

**Every practice's Xero chart of accounts is different** — you cannot match on account codes.
Classify by Xero account **type/class**, and map each org's accounts to a **standard cost
taxonomy**. Reuse the existing **`Standard_*` mapping system** (`Mappings/`, `Scripts/`) — the
same pattern already used to normalise other per-tenant reference data.

## 8. Xero API specifics

- **Auth:** OAuth2 authorization-code flow; per-org access discovered via the `connections`
  endpoint (`xero-tenant-id` header per call).
- **Rate limits:** 60 calls/min and 5,000 calls/day **per org**, plus an app-level ceiling →
  paginate, back off on `429`, and stagger the nightly run across orgs.
- **Incremental:** `If-Modified-Since` / `UpdatedDateUTC` to pull deltas after the first full load.
- **Certification:** connecting **>25 orgs** requires Xero's partner-app review — **start early**.

## 9. Open decisions (to confirm with the requester)

1. Where the "Connect Xero" consent flow lives (recommend: embed app tenant-admin).
2. Org → site mapping: one org per site, or one org per group split by tracking categories?
3. Overhead/shared-cost allocation across sites (or leave at group grain).
4. Historical depth (Journals from what date).
5. Owner of the Xero app registration + partner certification.

## 10. Key risks

- Heterogeneous charts of accounts (mitigated by §7 standard taxonomy).
- Xero partner-app certification lead time for scale.
- Refresh-token rotation / secure per-tenant storage.
- Multi-site-in-one-org attribution + overhead allocation.
- Compliance: Controller financial data, new sub-processor.
