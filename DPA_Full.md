# Data Processing Agreement (DPA) — Analytically

**Template / draft — version 1.0, 2026-06-18 (combined 2026-06-24). Not legal advice; have
it reviewed by a qualified adviser before use.** Items in **[CONFIRM]** need a
commercial/legal decision.

This single document contains the Data Processing Agreement together with **Schedule 1
(Details of Processing)** and **Schedule 2 (Technical & Organisational Measures)**.

This Data Processing Agreement ("**DPA**") forms part of the service agreement (the
"**Agreement**") between:

- the **customer practice** ("**Controller**"), and
- **Analytically Limited** (company number **16242443**) ("**Processor**"),

and governs the Processor's processing of personal data on the Controller's behalf under
**UK GDPR Article 28** and the Data Protection Act 2018.

---

## 1. Definitions

Terms "personal data", "processing", "controller", "processor", "data subject",
"personal data breach" and "special-category data" have the meanings in UK GDPR. The
**details of processing** (subject matter, duration, nature/purpose, data types, data
subjects) are set out in **Schedule 1** (below). The **technical and organisational
measures** are set out in **Schedule 2** (below) and in `SECURITY_OVERVIEW.md` /
`INFORMATION_SECURITY_POLICY.md`.

## 2. Roles

The Controller (practice) determines the purposes and means of processing its patients'
data. The Processor (Analytically) processes that data **only to provide, secure,
maintain and support the service**.

## 3. Processing on documented instructions

The Processor processes personal data **only on the Controller's documented instructions**
(including the Agreement, this DPA, and the Controller's configuration of the service),
and as required by law. The Processor will inform the Controller if, in its opinion, an
instruction infringes data-protection law. The Processor will **not** sell, share, or use
the data for advertising or model training.

## 4. Confidentiality

The Processor ensures that persons authorised to process the personal data are bound by
confidentiality and are subject to least-privilege access (see `ACCESS_MODEL.md`).

## 5. Security (Article 32)

The Processor implements appropriate technical and organisational measures — summarised
in **Schedule 2** — including UK residency, encryption in transit and at rest,
per-tenant row-level security with automated isolation tests, MFA on production access,
separated dev/prod with synthetic dev data, data minimisation, and logging.

## 6. Sub-processors

- The Controller provides **general written authorisation** for the Processor to engage
  sub-processors. The current list is maintained in **`SUB_PROCESSOR_REGISTER.md`**.
- The Processor imposes data-protection obligations on each sub-processor equivalent to
  those in this DPA, and remains liable for their performance.
- The Processor will give the Controller **prior notice** of any intended addition or
  replacement of a sub-processor, and a **reasonable opportunity to object** on
  reasonable data-protection grounds, on **30 days' prior notice**.

## 7. Assistance with data-subject rights

Taking account of the nature of the processing, the Processor assists the Controller (by
appropriate technical and organisational measures, insofar as possible) to respond to
data-subject requests — access, rectification, erasure, restriction, portability,
objection. Erasure/DSAR is currently handled **manually by Controller and Processor
together** (see DPIA §6.3). The Processor promptly forwards any request it receives
directly to the Controller.

## 8. Personal data breach

The Processor notifies the Controller **without undue delay, and in any event targeting
within 48 hours**, after becoming aware of a personal data breach affecting the
Controller's data, with the information the Controller needs to meet its own notification
obligations. Security contact: **security@analytically.info**.

## 9. DPIA & prior consultation

The Processor provides reasonable assistance to the Controller with data-protection
impact assessments and prior consultation with the ICO, taking account of the nature of
processing and information available to the Processor. (This platform's DPIA is available
to support the Controller's own assessment.)

## 10. Return & deletion

On termination of the service, or on the Controller's request: access is **suspended
immediately**, a **30-day recovery window** applies, and the Controller's personal data
is **permanently deleted within 90 days**, unless retention is required by law. The
upstream Dentally system remains the Controller's system of record. The Processor
confirms deletion on request.

## 11. Audits & inspections

The Processor makes available information necessary to demonstrate compliance with
Article 28 (e.g. this DPA, the DPIA, the Security Overview, sub-processor register), and
allows for and contributes to audits, including inspections, by the Controller or an
auditor it mandates. To protect other customers' security and confidentiality, this is
satisfied by **up to one remote audit request per year** (the Processor providing the
relevant documentation and written responses), on reasonable notice — with on-site or more
frequent audits only where required by a supervisory authority or following a confirmed breach.

## 12. International transfers

The Controller's **customer/patient data is hosted in the UK**, and the Processor
does not itself transfer that data outside the UK. The Processor relies on Microsoft as a
sub-processor (§6); certain Microsoft platform-level operations — e.g. authentication
(Entra ID), support and telemetry — may involve processing outside the UK under
Microsoft's own data-protection terms and transfer safeguards. **Any international
transfer of personal data will be subject to an appropriate UK GDPR transfer mechanism**
(e.g. the UK International Data Transfer Agreement / Addendum or an adequacy decision).

## 13. Liability, term & governing law

Liability is as set out in the Agreement. This DPA runs for the term of the Agreement and
survives to the extent needed for return/deletion obligations. Governed by the laws of
**England and Wales.**

---

# Schedule 1 — Details of Processing

Schedule to the Data Processing Agreement between the practice (**Controller**) and
Analytically (**Processor**), per UK GDPR Article 28(3). Describes the processing the
Processor carries out on the Controller's behalf.

### 1. Subject matter

Provision of a business-intelligence / operational-analytics service over the
Controller's Dentally practice-management data.

### 2. Duration

For the term of the service agreement. On termination: access suspended immediately,
30-day recovery window, permanent deletion of the Controller's data within 90 days.

### 3. Nature and purpose of processing

Ingesting the Controller's data from the Dentally API; transforming it into a
dimensional analytics model; presenting aggregated dashboards and patient-level
operational lists (e.g. overdue recalls, outstanding balances) to the Controller's
authorised users, including contact details to enable the Controller to contact its
own patients. The Processor does **not** use the data for any other purpose, and does
**not** sell, share or use it for advertising or model
training.

### 4. Types of personal data processed

**Patient (data subjects of the Controller):**
- Patient identifier (Dentally ID)
- Name (first, last, preferred)
- Contact details: email address, mobile phone, home phone
- Contact preferences: use-email / use-SMS flags and preferred phone (which stored number to use)
- Marketing-consent flag
- Appointment data: dates, status, attendance/DNA, cancellations, recall dates/intervals
- Treatment data: structured treatment **codes, categories, values** and standard
  treatment names (NHS band where applicable)
- Financial data: amounts invoiced, paid, outstanding
- Acquisition source; assigned dentist/hygienist; site

**Practice staff (e.g. practitioners) — limited:**
- Name, professional identifiers, role/site, performance-related aggregates

**NOT processed** (excluded by design): special-category / health-identifying data —
clinical notes, treatment free-text descriptions, medical history, medical-alert
content, NHS number, NI number, date of birth, gender, ethnicity, full address,
diagnostic images, uploaded documents, correspondence.

### 5. Categories of data subjects

- The Controller's **patients** (active patients hold identifying/contact data;
  inactive patients' identifying data is obfuscated).
- The Controller's **staff/practitioners**.
- The Controller's **authorised application users**.

### 6. Special-category data

By design, the Processor does **not** process Article 9 special-category data. Treatment
information is limited to structured codes/categories/values; no free-text clinical
content or health identifiers are stored. (Treatment category can imply care received;
it is retained as the minimum needed for clinical-performance analytics and is held under
the same controls.)

### 7. Processing operations

Collection (API ingestion), storage, organisation/structuring, transformation,
retrieval, presentation to authorised users, obfuscation (inactive patients), and
erasure (on termination / retention rules).

### 8. Sub-processors

Maintained canonically in **`SUB_PROCESSOR_REGISTER.md`**:
- **Microsoft** — Azure (hosting, UK), Microsoft Fabric / Power BI (data
  warehouse + embedded analytics), and Entra ID (authentication).
- **GitHub** (a Microsoft company) — source control & CI/CD deployment automation;
  processes no patient data.

Customer-controlled integrations connected by the practice are **not** sub-processors of
the Processor and remain the Controller's responsibility.

### 9. Technical and organisational measures

See **Schedule 2** (below), the Security Overview and DPIA. Summary: UK residency;
encryption in transit and at rest; per-tenant row-level security with automated isolation
tests; MFA on all production-data access; separated dev/prod with synthetic dev data;
least-privilege, time-limited, logged production access; data minimisation (no
special-category or free-text clinical data); defined retention and deletion.

### 10. International transfers

The Controller's customer/patient data is hosted within the United Kingdom. Microsoft platform-level operations (e.g. Entra ID authentication, support,
telemetry) may involve limited processing outside the UK under Microsoft's own transfer
safeguards. Any international transfer of personal data is subject to an appropriate UK
GDPR transfer mechanism.

---

# Schedule 2 — Technical & organisational measures (summary)

| Area | Measure |
|---|---|
| **Data residency** | Customer/patient data hosted in Microsoft Azure / Fabric, in the **UK**; any international transfer subject to an appropriate UK GDPR transfer mechanism (§12) |
| **Encryption** | TLS in transit (HTTPS, `Encrypt=True` SQL); Microsoft-managed encryption at rest |
| **Tenant isolation** | Per-row `Tenant_ID` + Power BI row-level security (effective identity); **fail-closed** embed token; automated RLS coverage + isolation tests in CI |
| **Authentication** | Entra ID; **per-user MFA** on all human production access; break-glass admin excluded; automation via service principals (prod = GitHub OIDC, no stored secret) |
| **Access control** | Least-privilege via security groups; dev (synthetic data) cannot reach production; production access exceptional, time-limited, logged |
| **Environment separation** | Separate dev/prod workspaces, warehouses and app environments; no production data copied to dev |
| **Data minimisation** | No special-category or free-text clinical data; structured treatment codes/categories/values only; inactive patients pseudonymised |
| **Logging** | ETL/deploy auditing; structured app logs with correlation IDs; Entra + PBI activity logs retained ≥ 12 months |
| **Resilience** | Microsoft Fabric/OneLake durability; analytics rebuildable from source; source re-ingestible from Dentally |
| **Secure development** | Source-controlled, reviewed changes; versioned migrations via CI; secrets never committed; automated test gates |

*See `INFORMATION_SECURITY_POLICY.md` and `SECURITY_OVERVIEW.md` for the full description.*

---

*All key terms now set: Processor = Analytically Limited (company no. 16242443);
security contact security@analytically.info; 30-day sub-processor notice;
breach notification targeting 48 hours; one remote audit/year; governing law England &
Wales.*

***Still to confirm with the Controller before execution ([CONFIRM]):** exact
authorised-user roles (Schedule 1 §5) and the data-retention period for active practices
(see DPIA §6.2). **Have a qualified adviser review this combined document before use.***
