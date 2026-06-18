# DPA — Schedule 1: Details of Processing

Schedule to the Data Processing Agreement between the practice (**Controller**) and
Analytically (**Processor**), per UK GDPR Article 28(3). Describes the processing the
Processor carries out on the Controller's behalf.

---

## 1. Subject matter

Provision of a business-intelligence / operational-analytics service over the
Controller's Dentally practice-management data.

## 2. Duration

For the term of the service agreement. On termination: access suspended immediately,
30-day recovery window, permanent deletion of the Controller's data within 90 days.

## 3. Nature and purpose of processing

Ingesting the Controller's data from the Dentally API; transforming it into a
dimensional analytics model; presenting aggregated dashboards and patient-level
operational lists (e.g. overdue recalls, outstanding balances) to the Controller's
authorised users, including contact details to enable the Controller to contact its
own patients. The Processor does **not** use the data for any other purpose, and does
**not** sell, share or use it for cross-customer benchmarking, advertising, or model
training.

## 4. Types of personal data processed

**Patient (data subjects of the Controller):**
- Patient identifier (Dentally ID)
- Name (first, last, preferred)
- Contact details: email address, mobile phone, home phone
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

## 5. Categories of data subjects

- The Controller's **patients** (active patients hold identifying/contact data;
  inactive patients' identifying data is obfuscated).
- The Controller's **staff/practitioners**.
- The Controller's **authorised application users**.

## 6. Special-category data

By design, the Processor does **not** process Article 9 special-category data. Treatment
information is limited to structured codes/categories/values; no free-text clinical
content or health identifiers are stored. (Treatment category can imply care received;
it is retained as the minimum needed for clinical-performance analytics and is held under
the same controls.)

## 7. Processing operations

Collection (API ingestion), storage, organisation/structuring, transformation,
retrieval, presentation to authorised users, obfuscation (inactive patients), and
erasure (on termination / retention rules).

## 8. Sub-processors

Maintained canonically in **`SUB_PROCESSOR_REGISTER.md`**:
- **Microsoft** — Azure (hosting, UK South), Microsoft Fabric / Power BI (data
  warehouse + embedded analytics), and Entra ID (authentication).
- **GitHub** (a Microsoft company) — source control & CI/CD deployment automation;
  processes no patient data.

Customer-controlled integrations connected by the practice are **not** sub-processors of
the Processor and remain the Controller's responsibility.

## 9. Technical and organisational measures

See the Security Overview and DPIA. Summary: UK-South residency; encryption in transit
and at rest; per-tenant row-level security with automated isolation tests; MFA on all
production-data access; separated dev/prod with synthetic dev data; least-privilege,
time-limited, logged production access; data minimisation (no special-category or
free-text clinical data); defined retention and deletion.

## 10. International transfers

The Controller's customer/patient data is hosted within the United Kingdom (Azure UK
South). Microsoft platform-level operations (e.g. Entra ID authentication, support,
telemetry) may involve limited processing outside the UK under Microsoft's own transfer
safeguards. Any international transfer of personal data is subject to an appropriate UK
GDPR transfer mechanism.

---

*Placeholders to confirm with the Controller: exact authorised-user roles, data-retention
period for active practices, security contact, and breach-notification process.*
