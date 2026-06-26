# Information Security Policy — Analytically

**Version 1.0 — 2026-06-18.** Owner: Director / Data Protection lead (currently the
sole developer-administrator). Review: at least annually, or on any material change to
the platform, hosting, or organisation. This is an internal policy summary, not legal advice.

---

## 1. Purpose & scope

This policy sets out how Analytically protects the confidentiality, integrity and
availability of the data it processes — principally **dental practice and patient data**
ingested from Dentally and presented through embedded analytics. It applies to all
systems, code, accounts and people involved in operating the platform.

## 2. Roles & responsibility

The organisation is currently a **single developer-administrator** who holds overall
responsibility for security and data protection. Duties are separated by **identity**
(see `ACCESS_MODEL.md`): development, operations/release, reporting and break-glass
administration use distinct accounts. As the organisation grows, these roles will be
held by different people.

## 3. Data classification & minimisation

- **Confidential — patient/practice data:** identity & contact details (active patients),
  appointment, treatment (structured codes/categories/values only), and financial data.
- **By design we do NOT hold** special-category/health-identifying data or free-text
  clinical content (no clinical notes, medical history, NHS/NI numbers, DOB, gender,
  ethnicity, full address, images or correspondence) — removed end-to-end (releases
  V011–V012) and verified in the regression suite. Inactive patients are pseudonymised
  in the analytics layer (V013–V014). See the DPIA §2/§7.

## 4. Access control

- **Least privilege.** Access is granted via Entra ID **security groups**, not per-user.
- The **day-to-day development identity cannot reach production or real patient data**
  (dev uses synthetic data only).
- **Production access is exceptional** — used only for support, incident or maintenance,
  time-limited, and logged.
- End-users reach data only through the app, scoped to **their own tenant** by row-level
  security with a **fail-closed** embed token.

## 5. Authentication (MFA)

Authentication is **Microsoft Entra ID**. **Per-user MFA is enforced on every human
account** except a deliberately MFA-exempt **break-glass Global Admin** kept as the
recovery path. Deployment automation is non-interactive: the **production** service
principal authenticates via **GitHub OIDC with no stored secret**; the dev service
principal's secret is dev-only. (Migration to Conditional Access is planned if Entra ID
P1 becomes available.)

## 6. Encryption

- **In transit:** HTTPS/TLS everywhere — browser, SQL (`Encrypt=True`), platform APIs.
- **At rest:** Microsoft-managed encryption across Fabric/OneLake and Azure (customer-
  managed keys are a future enhancement).

## 7. Hosting & data residency

Microsoft **Azure** (Container Apps) and Microsoft **Fabric/OneLake**, **UK**
(UK data residency). Customer/patient data is stored in the UK; certain Microsoft
platform-level operations (Entra ID, support, telemetry) may process limited data outside
the UK under Microsoft's safeguards, and **any international transfer is subject to an
appropriate UK GDPR transfer mechanism** (DPA §12). Development and production are
**fully separated** — separate workspaces, warehouses and app environments; **no
production data is copied into development**.

## 8. Secure development & change management

- All infrastructure and warehouse changes are **source-controlled and reviewed** (Git).
- Warehouse changes deploy via **versioned migration manifests** through CI; production
  warehouse deploys run in **GitHub Actions via OIDC** (no laptop holds prod credentials).
- **Secrets are never committed** (gitignored; CI secret store / OIDC); the container
  image build excludes all environment files.
- An **automated test suite** (auth/tenant-scoping, RLS coverage & isolation, data
  regression) gates changes; post-deploy `/health` smoke tests run in CI.

## 9. Logging & monitoring

- ETL and deploy activity are audited (`Audit` schema, `Migrate.Deploy_Log`).
- The application emits **structured logs with per-request correlation IDs** (`X-Request-ID`).
- **Entra sign-in logs, Power BI/Fabric activity logs and application logs are retained
  for a minimum of 12 months.** (Activity-log export enablement is in progress.)
- A consolidated per-user **read-access audit** is on the roadmap.

## 10. Backup & recovery

Built on Microsoft Fabric/OneLake platform durability and redundancy. Analytics layers
are **rebuildable from source**, and source data is **re-ingestible from Dentally**
(the system of record). Formal RPO/RTO and Fabric point-in-time-restore retention are
**[CONFIRM]**.

## 11. Incident & breach response

Security issues are reported to **security@analytically.info**. On a suspected
personal-data breach: contain, assess, and **notify affected customers in line with UK
GDPR timelines** (and the ICO where applicable, within 72 hours of becoming aware). The
controller (practice) is notified without undue delay.

## 12. Vendor / sub-processor management

Third-party services are listed and maintained in the **`SUB_PROCESSOR_REGISTER.md`**.
New sub-processors are added to the register and the customer DPA, and customers are
notified, **before** the service goes live with their data.

## 13. Data retention & disposal

- Patient identifying/contact data is held for **active patients only**; inactive
  patients are pseudonymised in the analytics layer.
- **If a practice leaves:** access suspended immediately, **30-day recovery window**, then
  permanent deletion of the practice's data **within 90 days**.
- DSAR / erasure handled manually by controller + processor (see DPIA §6.3).

## 14. Physical & endpoint security

Operations are cloud-based (no on-premises servers). Administrative endpoints use
full-disk encryption, screen-lock, and up-to-date OS/security patches. **[CONFIRM
endpoint baseline as the team grows.]**

## 15. Policy review

Reviewed at least **annually** and after any material change. Related documents: `DPIA.md`,
`ACCESS_MODEL.md`, `SECURITY_OVERVIEW.md`, `SUB_PROCESSOR_REGISTER.md`, `DPA.md` (+ Schedule 1),
`PENETRATION_TEST_SCOPE.md`.
