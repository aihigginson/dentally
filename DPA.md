# Data Processing Agreement (DPA) — Analytically

**Template / draft — version 1.0, 2026-06-18. Not legal advice; have it reviewed by a
qualified adviser before use.** Items in **[CONFIRM]** need a commercial/legal decision.

This Data Processing Agreement ("**DPA**") forms part of the service agreement (the
"**Agreement**") between:

- the **customer practice** ("**Controller**"), and
- **Analytically [legal entity / company no. — CONFIRM]** ("**Processor**"),

and governs the Processor's processing of personal data on the Controller's behalf under
**UK GDPR Article 28** and the Data Protection Act 2018.

---

## 1. Definitions

Terms "personal data", "processing", "controller", "processor", "data subject",
"personal data breach" and "special-category data" have the meanings in UK GDPR. The
**details of processing** (subject matter, duration, nature/purpose, data types, data
subjects) are set out in **Schedule 1** (`DPA_SCHEDULE_1.md`). The **technical and
organisational measures** are set out in **Schedule 2** (below) and in
`SECURITY_OVERVIEW.md` / `INFORMATION_SECURITY_POLICY.md`.

## 2. Roles

The Controller (practice) determines the purposes and means of processing its patients'
data. The Processor (Analytically) processes that data **only to provide the service**.

## 3. Processing on documented instructions

The Processor processes personal data **only on the Controller's documented instructions**
(including the Agreement, this DPA, and the Controller's configuration of the service),
and as required by law. The Processor will inform the Controller if, in its opinion, an
instruction infringes data-protection law. The Processor will **not** sell, share, or use
the data for advertising, cross-customer benchmarking, or model training.

## 4. Confidentiality

The Processor ensures that persons authorised to process the personal data are bound by
confidentiality and are subject to least-privilege access (see `ACCESS_MODEL.md`).

## 5. Security (Article 32)

The Processor implements appropriate technical and organisational measures — summarised
in **Schedule 2** — including UK-South residency, encryption in transit and at rest,
per-tenant row-level security with automated isolation tests, MFA on production access,
separated dev/prod with synthetic dev data, data minimisation, and logging.

## 6. Sub-processors

- The Controller provides **general written authorisation** for the Processor to engage
  sub-processors. The current list is maintained in **`SUB_PROCESSOR_REGISTER.md`**.
- The Processor imposes data-protection obligations on each sub-processor equivalent to
  those in this DPA, and remains liable for their performance.
- The Processor will give the Controller **prior notice** of any intended addition or
  replacement of a sub-processor, and a **reasonable opportunity to object** on
  reasonable data-protection grounds. **[CONFIRM notice period — e.g. 30 days.]**

## 7. Assistance with data-subject rights

Taking account of the nature of the processing, the Processor assists the Controller (by
appropriate technical and organisational measures, insofar as possible) to respond to
data-subject requests — access, rectification, erasure, restriction, portability,
objection. Erasure/DSAR is currently handled **manually by Controller and Processor
together** (see DPIA §6.3). The Processor promptly forwards any request it receives
directly to the Controller.

## 8. Personal data breach

The Processor notifies the Controller **without undue delay** after becoming aware of a
personal data breach affecting the Controller's data, with the information the Controller
needs to meet its own notification obligations. **[CONFIRM target — e.g. within 48 hours.]**
Security contact: **[CONFIRM].**

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
auditor it mandates — subject to reasonable notice, confidentiality, frequency limits and
not compromising other customers' security. **[CONFIRM audit process / frequency.]**

## 12. International transfers

The Processor does **not** transfer the Controller's personal data outside the UK.
Processing and storage are within **Azure UK South**. Any future transfer would require an
appropriate UK GDPR transfer mechanism and prior notice.

## 13. Liability, term & governing law

Liability is as set out in the Agreement. This DPA runs for the term of the Agreement and
survives to the extent needed for return/deletion obligations. Governed by the laws of
**England and Wales [CONFIRM jurisdiction].**

---

## Schedule 1 — Details of processing

Set out in **`DPA_SCHEDULE_1.md`** (subject matter, duration, nature/purpose, data
types, data subjects, special-category position, sub-processors, TOMs summary,
international transfers).

## Schedule 2 — Technical & organisational measures (summary)

| Area | Measure |
|---|---|
| **Data residency** | Microsoft Azure / Fabric, **UK South**; no international transfers |
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

*Placeholders to finalise with the Controller: legal entity details, notice/breach
periods, audit process, security contact, and governing jurisdiction.*
