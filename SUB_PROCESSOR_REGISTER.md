# Sub-Processor Register — Analytically

**Last reviewed: 2026-06-30.** This register lists the third parties Analytically (the
**Processor**) uses to deliver the service, and what (if any) personal data each one
processes on behalf of customer practices (the **Controllers**). It is the canonical
list referenced by the DPIA (§13) and the customer DPA.

Customer/patient data is hosted within **Microsoft Azure / Microsoft Fabric, in the UK**
(UK data residency). Microsoft platform-level operations (e.g. Entra ID authentication,
support, telemetry) may involve limited processing outside the UK under Microsoft's own
transfer safeguards; **any international transfer of personal data is subject to an
appropriate UK GDPR transfer mechanism.**

---

## Current sub-processors

| # | Sub-processor | Service / role | Purpose | Personal data processed | Location | Basis |
|---|---|---|---|---|---|---|
| 1 | **Microsoft** | Microsoft Fabric / OneLake | Data warehouse, semantic model, embedded report hosting | **Yes** — patient identity (active), contact details, marketing consent, operational/financial/treatment analytics | UK | Microsoft Products & Services DPA |
| 2 | **Microsoft** | Azure (Container Apps + resource group) | Application & API hosting | **Yes** — tenant-scoped data served/rendered in transit to authenticated users | UK | Microsoft Products & Services DPA |
| 3 | **Microsoft** | Entra ID | Authentication & identity / access management | **Yes** — staff/user account identifiers & sign-in metadata; **not** patient data | UK / EU (Microsoft identity platform) | Microsoft Products & Services DPA |
| 4 | **GitHub** (a Microsoft company) | GitHub + GitHub Actions | Source control & CI/CD deployment automation | **No patient data** — application code, configuration & deployment pipelines only (prod deploys via OIDC) | — | GitHub DPA |
| 5 | **Web3Forms** | Public website enquiry form-to-email delivery | Routes enquiry submissions from the marketing site (`analytically.info`) to Analytically's inbox | **No patient/customer (Controller) data** — only prospect-submitted enquiry details (name, practice name, email, phone, message), i.e. Analytically's own marketing/prospect data | International | Web3Forms Terms & Privacy Policy |
| 6 | **Google** | Google Analytics 4 — public website usage analytics | Aggregate measurement of how visitors use the marketing site (`analytically.info`) | **No patient/customer (Controller) data** — public-website usage only (cookie identifiers, pages viewed, approximate location); GA4 does not store full IP addresses | International (Google, under its transfer safeguards) | Google Ads Data Processing Terms |

**Not a sub-processor:** the upstream **Dentally** practice-management system is the
Controller's own clinical record and **source of data**, not a sub-processor of Analytically.
Likewise, **any customer-controlled integrations** the practice chooses to connect are
**not** sub-processors of Analytically and remain under the Controller's responsibility.

---

## Change-notification commitment

- New sub-processors (or material changes to an existing one's role) are added to this
  register **and the customer DPA**, and customers are **notified in advance** of the
  service going live with their data, with a reasonable opportunity to object.
- **Web3Forms** (#5) and **Google Analytics** (#6) relate to the public marketing
  website only and process **no Controller data**; they are listed here for
  completeness/transparency. The website's cookie use is described in the
  [Cookie Policy](COOKIE_POLICY.md).
- Other candidate future additions that would require an update here: error tracking
  (e.g. Sentry / Azure Application Insights), email/notification providers handling
  **customer data**, support tooling. **None currently in use.**

*Maintained alongside `DPIA.md`, `DPA.md` (+ Schedule 1), and `SECURITY_OVERVIEW.md`.*
