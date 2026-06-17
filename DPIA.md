# Data Protection Impact Assessment (DPIA) — Analytically

**Draft, filled from the system's current state + `COMPLIANCE.md`.** Items needing a
business/policy decision are marked **[CONFIRM]** / **[DECISION NEEDED]**. Not legal advice.

---

## 1. Product and processing description

**1.1 Name:** Analytically (embedded analytics over a Dentally data warehouse on Microsoft Fabric).

**1.2 Primary purpose:** Practice performance management — and specifically: recall optimisation, revenue analysis, treatment conversion/clinical analysis, NHS (UDA) performance, staff/practitioner performance, and patient-retention/contactability. (Reports: Home, Revenue, Patient, Schedule, Clinical, NHS.)

**1.3 Intended users:** Practice owners, practice managers, and group management teams (primary); reception staff (to action operational lists e.g. overdue recalls / missing contact details); dentists & hygienists (own performance). Access is role-aware. **[CONFIRM the exact role list you want to support.]**

**1.4 Patient-level vs aggregated:** Reports are **primarily aggregated** (KPIs, trends, distributions). **Patient-level drill-through** is provided/intended for operational action (e.g. the list of patients behind an "overdue recalls" figure) showing the **minimum needed to act**: Patient ID, Name, the actionable attribute (recall due date / outstanding balance / missing-contact flag), and the contact detail required to act.
> **Data minimisation implemented (2026-06-17, release V011).** The analytics pipeline has been minimised **end-to-end** (data generator → Stage → Bronze → Silver → Gold → Power BI). The model now holds patient **name, contact details (email/phone), marketing consent, and operational/financial analytics only**. Special-category and excess-identifier fields (date of birth, gender, ethnicity, NHS/NI numbers, full address, medical alerts, emergency contacts, etc.) are **no longer collected or stored anywhere in the warehouse** (see §2 and §7). RLS additionally scopes everything per-tenant.

---

## 2. Data collected

Based on the Gold warehouse schema (`Dim_Patients`, fact tables). "Collected" = present in the warehouse/model; visibility in reports is narrower (§1.4). The table below reflects the **minimised** model after release V011 (2026-06-17).

**Patient identity**
| Field | Collected |
|---|---|
| Patient ID | Yes |
| First / Last / Preferred / Full Name | Yes |
| Date of Birth | **No** — removed (V011) |
| Age (years) / age band | **No** — removed (V011) |
| Gender | **No** — removed (V011) |
| Ethnicity | **No** — removed (V011; *special category*) |
| NHS Number / NI Number | **No** — removed (V011) |

**Contact data** — both the **values and "missing" flags** are present:
| Field | Collected |
|---|---|
| Email address | Yes (+ `Is_Email_Missing` flag) |
| Mobile / Home phone | Yes (+ `Is_Phone_Missing` flag) |
| Work phone | **No** — removed (V011) |
| Address (lines, town, county, postcode) | **No** — removed (V011) |
| Marketing consent (`Marketing_Consent`) | Yes |
| `Use_Email` / `Use_SMS` per-channel flags | **No** — removed (V011) |

**Appointment data:** appointment dates — Yes; status — Yes; missed/DNA — Yes; cancellations (+ reason) — Yes; recall information (dates, intervals, status) — Yes.

**Clinical data:** treatment codes — Yes; treatment categories — Yes; treatment values — Yes; medical alerts (`Medical_Alert` flag / `Medical_Alert_Text`) — **No** (removed V011); clinical notes — **Limited** (appointment `Notes` / `Treatment_Description` free-text in fact tables); medical history — No; X-rays / images / uploaded documents — **No**.

**Financial data:** treatment revenue — Yes; outstanding balances — Yes (`Total_Invoiced` − `Total_Paid`, invoices); payment history — Yes.

---

## 3. Data flow

**3.1 Import frequency:** Scheduled via a Fabric data pipeline — **[CONFIRM cadence; typically daily]**. Not real-time.

**3.2 Automated:** Yes — Fabric pipeline ingests from the Dentally API (Bronze) → Silver → Gold; no manual data entry.

**3.3 Practice authorises the API connection:** Yes — each tenant is configured with its own Dentally API credentials (`Audit.Tenants`); ingestion only runs with credentials the practice provides. **[CONFIRM the contractual/consent mechanism + data-processor agreement with each practice.]**

**3.4 Does data leave Microsoft Fabric?** Data is read out of Fabric in two intended ways, both **within Microsoft Azure (UK South — see §5.1)**: (a) the embedded Power BI reports render tenant-scoped data to the authenticated user's browser; (b) the Flask API reads tenant-scoped data (e.g. filters, targets) for the app. **No CSV exports, scheduled email reports, or report attachments are built into the product.** Native Power BI export-to-CSV/PDF may be available to users unless disabled at the report/capacity level — **[CONFIRM whether PBI export is disabled].**

---

## 4. User access

**4.1 Who in your company can access customer data:** End-users see **only their own tenant** (RLS, fail-closed). However, staff holding the **service-principal credentials / direct warehouse access** (developers, administrators) can technically query **all tenants'** data directly — RLS applies to the embed/app layer, **not** to direct SQL by the SP. So: *nobody by default* at the app layer; *administrators/developers* at the infrastructure layer. **[CONFIRM/define who holds those credentials and tighten if needed.]**

**4.2 Can support see patient-level information:** Potentially yes, via infrastructure access (no RLS on direct queries). **[CONFIRM the support-access model — recommend a least-privilege, audited path rather than shared SP access.]**

**4.3 MFA:** Authentication is Entra ID, which supports MFA; administrator accounts use MFA. **End-user MFA enforcement is an Entra Conditional Access policy — [CONFIRM it is enforced for all users].**

**4.4 Audit logs:** **Partial.** ETL execution and schema/deploy changes are audited (`Audit` schema; `Migrate.Deploy_Log`). Login events (Entra sign-in logs) and report/export activity (Power BI/Fabric activity logs) exist at the platform level. **There is no consolidated per-user *data-access (read)* audit within the product yet** — a known gap (`COMPLIANCE.md`). **[DECISION NEEDED: enable + retain Entra sign-in + PBI activity logs; define retention.]**

---

## 5. Hosting and security

**5.1 Stored in UK West?** **No — UK South.** The Azure resources (Container Apps, resource group) and Fabric capacity are in **UK South** (data residency is UK). **[CONFIRM whether "UK West" is a hard requirement; if so this is a gap to address.]**

**5.2 Backups encrypted:** Yes — Fabric/OneLake stores all data with Microsoft-managed encryption; platform redundancy applies to backups/durability.

**5.3 Backups retained / how long:** Fabric/OneLake provides platform durability/redundancy; source data is re-ingestible from Dentally and Gold is rebuildable from Bronze/Silver. **Explicit warehouse backup/point-in-time retention is not yet documented — [CONFIRM Fabric PITR/restore retention; RPO/RTO not yet defined].**

**5.4 Encrypted at rest:** Yes — Microsoft-managed keys (no customer-managed key configured; CMK is a TODO).

**5.5 Encrypted in transit:** Yes — HTTPS at the edge; SQL with `Encrypt=True`; PBI/Fabric APIs over TLS.

**5.6 Prod and dev separated:** **Yes** — separate Fabric workspaces + warehouses + Container Apps (`…-eljz…` prod / `…-4i26…` dev).

**5.7 Production data copied into development:** **No.** Dev uses synthetic test tenants; prod currently holds only a clearly-labelled "Demonstration" tenant (synthetic). No real patient data is copied from prod into dev. **[CONFIRM this remains policy as real tenants onboard.]**

---

## 6. Data retention

**6.1 If a customer leaves:** **[DECISION NEEDED — no formal policy yet.]** Recommended default: deactivate access immediately (`Audit.Tenants.Is_Active = 0`, remove `Application_Users`), then delete the tenant's warehouse data within a defined window (e.g. 30 or 90 days). Source of record remains the upstream Dentally system.

**6.2 How long historical data is kept while active:** Currently the warehouse mirrors the practice's Dentally history with no purge while active. **[DECISION NEEDED: define a retention schedule per data class, and a DSAR / right-to-erasure workflow — `COMPLIANCE.md` flags both as open.]**

---

## 7. Special-category data assessment

**7.1 Why patient-level data is needed:** To let practices **act** on operational issues the analytics surface — contact patients with overdue recalls, chase patients with missing contact details, follow up lapsed patients, and reconcile outstanding balances. The aggregate identifies *that* there is an issue; patient-level identifies *who* to contact.

**7.2 Could the objective be met without patient-level data?** For the **reporting/analytics** (dashboards, KPIs, trends) — **yes**, aggregates are sufficient and no PII is needed. For the **operational action** (reception contacting specific patients) — **no**; you need the patient's identity and contact detail to act.

**7.3 Fields actually required to identify a patient needing action:**
- **Required (retained):** Patient ID, Name, the actionable attribute (e.g. recall due date / outstanding balance / "no email on file" flag), and the contact detail needed to act (phone / email).
- **Not required — now removed (V011, 2026-06-17):** NHS Number, NI Number, Ethnicity, Gender, Date of Birth/Age, full Address, Work phone, Medical Alert flag/text, emergency contacts, title/middle name, and other excess identifiers. **★ Minimisation mitigation — DONE:** these special-category / excess-identifier fields have been removed from the **entire pipeline** — the data generator, the OneLake landing (Stage), and every warehouse layer (Bronze → Silver → Gold → Power BI). They are no longer ingested or stored. Verified end-to-end on dev and production (0 sensitive columns from `Stage.Patients` through to `PBI.[List Patients]`); the regression suite (45 integrity + 120 metric checks) passed against the minimised model.
- **Residual:** for the eventual **real** Dentally ingestion, the pipeline's API column mapping should also be trimmed so these fields are not pulled from the API in the first place (currently only synthetic/demo data flows; the warehouse drops the fields regardless). Tracked as the one remaining minimisation item.

---

## 8. Multi-tenancy

**8.1 Shared Fabric environment:** Yes — practices share a warehouse per environment.

**8.2 How tenants are separated:** **Shared warehouse with row-level security** — every row carries `Tenant_ID` (Bronze→Gold→PBI), and the Power BI `RLS` role filters every tenant-bearing table to the signed-in user's tenant(s) via effective identity. Dev and prod are separate workspaces (not per-tenant workspaces).

**8.3 Tenant isolation tested:** **Yes** — two automated CI gates: `Check_RLS_Coverage` (every tenant-bearing table has an RLS filter; caught + closed 2 real leaks) and `Check_RLS_Isolation` (behavioural — an impersonated user sees only their tenant, verified with another tenant's data present). The embed token is mandatory/fail-closed (refuses if RLS unconfigured or the user maps to no tenant).

---

## 9. Future features  _(foreseeable evolution)_

**9.1 AI features:** **[CONFIRM]** — none currently. Any AI feature touching patient data would need its own DPIA addendum.

**9.2 Benchmark practices against each other:** **[CONFIRM]** — not currently. If introduced, cross-tenant benchmarking must be **anonymised/aggregated** and designed so no tenant's data is identifiable to another — a material change requiring reassessment.

**9.3 Data used for product improvement:** **[CONFIRM]** — not currently. If yes, define lawful basis + anonymisation.

**9.4 Train ML models:** **[CONFIRM]** — not currently. Training on special-category data has significant DPIA implications and would need explicit assessment + lawful basis.

---

## 10. The most important question — a concrete metric and drill-through

The **Home** dashboard shows **Overdue Recalls** as an aggregate (e.g. *997 overdue recalls*). A practice manager or receptionist clicks the metric and **drills through to a patient list** — **Patient ID, Name, recall due date, and contact details (phone/email)** — filtered to the same site/period as the dashboard, so reception can contact those patients to rebook.

The aggregate (*997*) answers "is there a problem?"; the patient-level list is the **minimum data needed to act on it**. This is precisely why patient-level data is necessary and proportionate — and why the **identifying/contact** fields are required while the **special-category** fields (§7.3) are not.
