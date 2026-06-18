# Data Protection Impact Assessment (DPIA) — Analytically

**Draft, filled from the system's current state + `COMPLIANCE.md`.** Items needing a
business/policy decision are marked **[CONFIRM]** / **[DECISION NEEDED]**. Not legal advice.

---

## 1. Product and processing description

**1.1 Name:** Analytically (embedded analytics over a Dentally data warehouse on Microsoft Fabric).

**1.2 Primary purpose:** Practice performance management — and specifically: recall optimisation, revenue analysis, treatment conversion/clinical analysis, NHS (UDA) performance, staff/practitioner performance, and patient-retention/contactability. (Reports: Home, Revenue, Patient, Schedule, Clinical, NHS.)

**1.3 Intended users:** Practice owners, practice managers, and group management teams (primary); reception staff (to action operational lists e.g. overdue recalls / missing contact details); dentists & hygienists (own performance). Access is role-aware. **[CONFIRM the exact role list you want to support.]**

**1.4 Classification — operational analytics with patient-contact workflows.** Reports are **primarily aggregated** (KPIs, trends, distributions). The platform also provides **patient-level drill-through** for operational action (e.g. the list of patients behind an "overdue recalls" figure), showing the **minimum needed to act**: Patient ID, Name, the actionable attribute (recall due date / outstanding balance / missing-contact flag), and the contact detail required to act (phone / email). Reception/practice staff therefore *do* see real patient names and contact details for the contact workflow — so this is accurately described as an **operational analytics platform with patient contact workflows**, not a pure aggregate-only analytics tool.
> **Data minimisation implemented end-to-end (releases V011, 2026-06-17 and V012, 2026-06-18).** The pipeline (data generator → Stage → Bronze → Silver → Gold → Power BI) holds patient **name, contact details (email/phone), marketing consent, and operational/financial analytics only**. Removed and no longer collected or stored anywhere in the warehouse: special-category / excess identifiers (date of birth, gender, ethnicity, NHS/NI numbers, full address, medical alerts, emergency contacts — V011) **and all free-text clinical content** (appointment & treatment notes, treatment free-text descriptions — V012). Identifying/contact PII is held for **active patients only** — inactive patients are shown as "Inactive Patient" with contact removed (V013, §6.2). See §2 and §7. RLS additionally scopes everything per-tenant.

---

## 2. Data collected

Based on the Gold warehouse schema (`Dim_Patients`, fact tables). "Collected" = present in the warehouse/model; visibility in reports is narrower (§1.4). The table below reflects the **minimised** model after releases V011–V014 (June 2026).

**Patient identity**
| Field | Collected |
|---|---|
| Patient ID | Yes |
| First / Last / Preferred / Full Name | Yes — **active patients only** (inactive patients shown as "Inactive Patient", contact NULLed; §6.2) |
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

**Clinical data:** treatment codes — Yes; treatment categories — Yes; treatment values — Yes; standard treatment name (nomenclature) — Yes. **No free-text clinical content is collected or stored** — clinical notes, treatment free-text descriptions, medical alerts, medical history, correspondence, X-rays / images / uploaded documents are all **No**. (Appointment & treatment `Notes` / `Treatment_Description` / `Patient_Nomenclature` / `Description` removed in V012, 2026-06-18; medical alerts removed in V011.)

**Financial data:** treatment revenue — Yes; outstanding balances — Yes (`Total_Invoiced` − `Total_Paid`, invoices); payment history — Yes.

---

## 3. Data flow

**3.1 Import frequency:** Scheduled via a Fabric data pipeline — **[CONFIRM cadence; typically daily]**. Not real-time.

**3.2 Automated:** Yes — Fabric pipeline ingests from the Dentally API (Bronze) → Silver → Gold; no manual data entry.

**3.3 Practice authorises the API connection:** Yes — each tenant is configured with its own Dentally API credentials (`Audit.Tenants`); ingestion only runs with credentials the practice provides. **[CONFIRM the contractual/consent mechanism + data-processor agreement with each practice.]**

**3.4 Does data leave Microsoft Fabric?** Data is read out of Fabric in two intended ways, both **within Microsoft Azure (UK South — see §5.1)**: (a) the embedded Power BI reports render tenant-scoped data to the authenticated user's browser; (b) the Flask API reads tenant-scoped data (e.g. filters, targets) for the app. **No CSV exports, scheduled email reports, or report attachments are built into the product.** Native Power BI export-to-CSV/PDF may be available to users unless disabled at the report/capacity level — **[CONFIRM whether PBI export is disabled].**

---

## 4. User access

**4.1 Who can access customer data:** End-users see **only their own tenant** (Power BI RLS, fail-closed). Development is performed in a **separate development environment using synthetic data only**; the day-to-day development account can reach the dev workspace/warehouse but **not** production. Production access is restricted, used **only when required for support, incident investigation or maintenance**, is **time-limited and removed when the task is complete**, and is **logged** through platform audit controls. The organisation currently consists of a **single developer-administrator** — so the honest, accurate statement is: access to customer data is restricted to authorised personnel on a least-privilege basis, production access is exceptional and audited, and no one accesses customer data through the app layer outside their own tenant. As the organisation grows, production access will be governed by privileged-access management and role separation.

**4.2 Can support see patient-level information:** Only the single developer-administrator, via the controlled production-access path above (least-privilege, time-limited, logged) and only when operationally necessary. There is no routine or shared support access to patient data.

**4.3 MFA:** Authentication is Entra ID. **MFA is enforced (Entra Conditional Access) on every account with access to the production database**, including administrator/production access. The dev-only account operates exclusively against synthetic data with no production access and is exempt from repeated MFA prompts so development is not impeded.

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

**6.1 If a customer (practice) leaves:** Access is **suspended immediately** (`Audit.Tenants.Is_Active = 0`, `Application_Users` removed), a **30-day recovery window** applies (in case of accidental or disputed termination), and the tenant's warehouse data is **permanently deleted within 90 days**. The source of record remains the upstream Dentally system.

**6.2 Retention of patient data while a practice is active — PII held for active patients only.** Identifying/contact data (name, email, phone) is **retained only for active patients**, because the operational purpose (contacting patients) only applies to them. When a patient becomes **inactive**, their **real name is replaced with the placeholder "Inactive Patient"** and their **contact details (email, phone) are removed (set to NULL)** across the analytics layers (Silver → Gold → Power BI) — so inactive patients remain *identifiable as inactive* on operational reports (e.g. recalls) but are no longer contactable and carry no personal identifiers; non-identifying operational/financial history is retained for trend analytics. **Live on dev and production (release V013, 2026-06-18).** Because their contact is deliberately removed, inactive patients are **not** flagged as "missing contact" and do **not** appear on contact/recall action lists (release V014). Active-patient history is retained while the practice is active **[CONFIRM the period — full Dentally history vs e.g. last 7 years]**. A **DSAR / right-to-erasure workflow** remains **[DECISION NEEDED]** (note: erasure is materially simplified by the minimisation above and by inactive-patient obfuscation).

---

## 7. Special-category data assessment

**7.1 Why patient-level data is needed:** To let practices **act** on operational issues the analytics surface — contact patients with overdue recalls, chase patients with missing contact details, follow up lapsed patients, and reconcile outstanding balances. The aggregate identifies *that* there is an issue; patient-level identifies *who* to contact.

**7.2 Could the objective be met without patient-level data?** For the **reporting/analytics** (dashboards, KPIs, trends) — **yes**, aggregates are sufficient and no PII is needed. For the **operational action** (reception contacting specific patients) — **no**; you need the patient's identity and contact detail to act.

**7.3 Fields actually required to identify a patient needing action:**
- **Required (retained):** Patient ID, Name, the actionable attribute (e.g. recall due date / outstanding balance / "no email on file" flag), and the contact detail needed to act (phone / email).
- **Not required — now removed (V011, 2026-06-17):** NHS Number, NI Number, Ethnicity, Gender, Date of Birth/Age, full Address, Work phone, Medical Alert flag/text, emergency contacts, title/middle name, and other excess identifiers. **★ Minimisation mitigation — DONE:** these special-category / excess-identifier fields have been removed from the **entire pipeline** — the data generator, the OneLake landing (Stage), and every warehouse layer (Bronze → Silver → Gold → Power BI). They are no longer ingested or stored. Verified end-to-end on dev and production (0 sensitive columns from `Stage.Patients` through to `PBI.[List Patients]`); the regression suite (45 integrity + 120 metric checks) passed against the minimised model.
- **Free-text clinical content — removed (V012, 2026-06-18):** all free-text fields that could contain unstructured sensitive information (appointment `Notes`, treatment `Treatment_Description` / `Description` / `Patient_Nomenclature` / `Patient_Description`, and config `Notes`) have been **dropped from the entire warehouse and Power BI**, keeping only structured treatment code / category / value / standard nomenclature. This eliminates the highest-variance privacy risk (free text is where unexpected special-category data appears). Verified 0 free-text columns from Bronze through to the PBI presentation layer, dev and production. **Net effect: the platform does not process clinical notes, medical histories, correspondence, uploaded documents, diagnostic images, NHS numbers, ethnicity, addresses or other special-category clinical content.**
- **Residual:** for the eventual **real** Dentally ingestion, the pipeline's API column mapping should also be trimmed so these fields are not pulled from the API at all (currently only synthetic/demo data flows; the warehouse drops the fields regardless). Tracked as the one remaining minimisation item.

---

## 8. Multi-tenancy

**8.1 Shared Fabric environment:** Yes — practices share a warehouse per environment.

**8.2 How tenants are separated:** **Shared warehouse with row-level security** — every row carries `Tenant_ID` (Bronze→Gold→PBI), and the Power BI `RLS` role filters every tenant-bearing table to the signed-in user's tenant(s) via effective identity. Dev and prod are separate workspaces (not per-tenant workspaces).

**8.3 Tenant isolation tested:** **Yes** — two automated CI gates: `Check_RLS_Coverage` (every tenant-bearing table has an RLS filter; caught + closed 2 real leaks) and `Check_RLS_Isolation` (behavioural — an impersonated user sees only their tenant, verified with another tenant's data present). The embed token is mandatory/fail-closed (refuses if RLS unconfigured or the user maps to no tenant).

---

## 9. Future features  _(foreseeable evolution)_

**9.1 AI features:** **[CONFIRM]** — none currently. Any AI feature touching patient data would need its own DPIA addendum.

**9.2 Benchmark practices against each other:** **Not currently planned.** Cross-practice benchmarking (e.g. "your recall conversion is in the top 25% of comparable practices") is a recognised future commercial opportunity but is **not in scope for the first release**. If introduced, it must use **aggregated and anonymised data only and must not identify individual patients or practices** to one another — a material change requiring DPIA reassessment.

**9.3 Data used for product improvement:** **[CONFIRM]** — not currently. If yes, define lawful basis + anonymisation.

**9.4 Train ML models:** **[CONFIRM]** — not currently. Training on special-category data has significant DPIA implications and would need explicit assessment + lawful basis.

---

## 10. The most important question — a concrete metric and drill-through

The **Home** dashboard shows **Overdue Recalls** as an aggregate (e.g. *997 overdue recalls*). A practice manager or receptionist clicks the metric and **drills through to a patient list** — **Patient ID, Name, recall due date, and contact details (phone/email)** — filtered to the same site/period as the dashboard, so reception can contact those patients to rebook.

The aggregate (*997*) answers "is there a problem?"; the patient-level list is the **minimum data needed to act on it**. This is precisely why patient-level data is necessary and proportionate — and why the **identifying/contact** fields are required while the **special-category** fields (§7.3) are not.

---

## 11. Risk register (residual, after controls)

| # | Risk | Likelihood | Impact | Key controls in place | Residual |
|---|------|-----------|--------|-----------------------|----------|
| 1 | **External breach** | Low | High | Microsoft-managed encryption at rest + TLS in transit; Entra auth + MFA on prod-DB access; UK-South residency; separate dev/prod; secrets gitignored / in CI secret store | **Medium** |
| 2 | **Insider misuse** (admin/SP querying all tenants) | Low | Medium-High | Single developer-administrator; prod access exceptional, time-limited, logged; dev uses synthetic data only; SP credentials not held in the local dev path (being split dev/prod) | **Medium** |
| 3 | **Tenant data leakage** (one practice sees another) | Low | High | Per-row `Tenant_ID` + Power BI RLS (effective identity); fail-closed embed token; two automated CI gates (`Check_RLS_Coverage`, `Check_RLS_Isolation`) | **Low-Medium** |
| 4 | **Excessive data collection** | Low | Medium | Data minimised end-to-end (V011/V012); only name, contact, marketing consent + structured operational/financial/treatment-category data | **Low** |
| 5 | **Clinical sensitivity exposure** (special-category / free text) | Low | High | All special-category fields + **all free-text clinical content removed** (V011/V012); no notes, medical history, images, correspondence | **Low** |
| 6 | **Re-identification** (patient identifiable in drill-through) | n/a | — | Inherent and necessary for the contact workflow; minimised to the fields needed to act; per-tenant scoped; PII held for active patients only | **Accepted & necessary** |
| 7 | **Data-minimisation failure** (sensitive field re-introduced) | Low | Medium | Schema is source-controlled + reviewed; regression suite; minimisation documented here | **Low** |
| 8 | **Insufficient read-audit / breach detection** | Medium | Medium | ETL + deploy auditing present; Entra sign-in + Fabric/PBI activity logs available at platform level | **Medium — [enable + retain; define retention]** |

**Overall residual risk: Medium-Low and acceptable with controls** — a normal posture for a healthcare-analytics SaaS. The remaining material items are *operational* (production-access controls, read-audit logging, retention/DSAR workflow) rather than data-model issues.

---

## 12. Penetration testing

An independent penetration test is **planned prior to launch** (not yet performed). Scope will cover the embedded app + auth flow, the embed-token/RLS isolation boundary, and the public endpoints. Deferred until the platform is launch-ready to avoid re-testing after material changes.
