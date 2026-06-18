# Analytically — Security Overview

A short, customer-facing summary of how Analytically protects practice and patient
data. For the full assessment see the DPIA; for the contractual data categories see
the DPA Schedule 1.

---

## What Analytically is

Analytically is a business-intelligence platform for dental practices. It reads a
practice's data from Dentally, transforms it into analytics, and presents dashboards
and operational lists (e.g. overdue recalls) through secure embedded reports. It is an
**operational analytics platform with patient-contact workflows**: most output is
aggregated, with patient-level drill-through provided where staff need to act
(e.g. contacting patients due a recall).

## What data we process

We process the **minimum needed** for analytics and the contact workflow:

- Patient **name** and **contact details** (email, phone), marketing-consent flag.
- **Appointment** data (dates, status, attendance, cancellations, recalls).
- **Treatment** data as **structured codes, categories and values** (plus the standard
  treatment name).
- **Financial** data (invoiced, paid, outstanding).

**We do *not* collect or store** clinical notes, treatment free-text descriptions,
medical histories, correspondence, uploaded documents or diagnostic images, nor
NHS/NI numbers, date of birth, gender, ethnicity, full addresses, or medical-alert
content. Patient identifying/contact data is held **only for active patients**;
inactive patients' identifying data is obfuscated.

## Hosting and data residency

- Hosted on **Microsoft Azure** and **Microsoft Fabric** in the **UK South** region
  (data residency: United Kingdom).
- Sub-processor: **Microsoft** (Azure, Fabric/Power BI). Authentication via **Microsoft
  Entra ID**.

## Encryption

- **In transit:** HTTPS/TLS everywhere (browser, SQL connections, platform APIs).
- **At rest:** Microsoft-managed encryption across the data platform.

## Access control and tenant isolation

- Each practice (tenant) sees **only its own data**, enforced by **row-level security**
  on every table, applied through the embedded report's effective identity. The access
  token is **fail-closed** (no token is issued if a user maps to no tenant).
- Tenant isolation is protected by **automated tests in our deployment pipeline** that
  check every data table is tenant-filtered and that an impersonated user cannot see
  another tenant's data.
- **Multi-factor authentication** is enforced on all accounts with access to production
  data. Development is performed in a **separate environment with synthetic data**;
  production access is restricted, used only when required, time-limited and logged.
- **Development and production are fully separated** (separate workspaces, warehouses and
  application environments). **No production data is copied into development.**

## Retention

- **Active practice:** patient identifying/contact data retained only while patients are
  active; inactive patients' identifying data is obfuscated.
- **If a practice leaves:** access suspended immediately, a 30-day recovery window, then
  permanent deletion of the practice's data within 90 days. Dentally remains the system
  of record.

## Reliability and recovery

- Built on Microsoft Fabric/OneLake platform durability. Analytics layers are rebuildable
  from source, and source data is re-ingestible from Dentally.

## Responsible disclosure / incidents

- Security issues can be reported to **[security contact — CONFIRM]**. We will acknowledge,
  investigate, and notify affected customers of any personal-data breach in line with UK
  GDPR timelines.

## Status / roadmap

- Independent penetration test planned prior to launch.
- Consolidated read-access audit logging and a formal DSAR workflow are on the roadmap.

*Items marked CONFIRM are being finalised. This overview is a summary, not a contract;
the DPA governs the processing relationship.*
