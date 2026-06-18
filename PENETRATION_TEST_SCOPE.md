# Penetration Test Scope — Analytically

**Draft scope, version 1.0 — 2026-06-18.** For an **independent** penetration test to be
performed **prior to launch / before onboarding real patient data**. Share with the
chosen testing provider as the basis for their statement of work.

---

## 1. Objectives

Provide independent assurance that, before real patient data is onboarded:

1. The **multi-tenant isolation boundary** cannot be bypassed — no user/tenant can reach
   another tenant's data.
2. **Authentication and the embed-token flow** cannot be abused to obtain data without a
   valid, correctly-scoped identity.
3. The **public-facing application and API** are free of high/critical web-application
   vulnerabilities (OWASP Top 10 class).
4. **Secrets and configuration** are not exposed.

## 2. In scope

| Asset | Notes |
|---|---|
| **Embedded analytics web app** (`dev.analytically.info` test instance) | UI, session handling, public routes |
| **Authentication flow** | Entra ID sign-in, token acquisition, session/cookie handling, MSAL flow |
| **Embed-token / RLS isolation boundary** | The server-side embed-token issuance and Power BI row-level-security effective-identity enforcement — the core tenant-isolation control |
| **Application API endpoints** | e.g. embed-token, filters, targets, `/me`, auth-config, `/health` — authZ, injection, IDOR/tenant-scoping |
| **Hosting surface** | Azure Container App ingress / TLS configuration (application layer) |
| **Configuration exposure** | Secrets in responses/headers/source maps; verbose errors; `.env`/build-artifact leakage |

## 3. Out of scope

- **Microsoft platform internals** — Azure, Microsoft Fabric/OneLake, Power BI service and
  Entra ID infrastructure (covered by Microsoft's own assurance; do not test Microsoft-owned
  infrastructure beyond our configuration of it).
- **Denial-of-service / volumetric / load testing.**
- **Physical, social-engineering and phishing** attacks against staff. **[CONFIRM if any
  social-engineering is wanted — default: excluded.]**
- The upstream **Dentally** API/system (third-party source of record).
- **Production with real patient data** — testing is against a dedicated test tenant with
  **synthetic data only** (see §5).

## 4. Test types / focus areas

- **Authentication & session:** token validation (signature, audience), session fixation,
  logout, token replay, the localStorage ID-token cache, redirect handling.
- **Authorisation & multi-tenant isolation (priority):** attempt cross-tenant access via
  manipulated embed tokens, identity/claims tampering, parameter/IDOR manipulation, and
  RLS-bypass attempts; confirm **fail-closed** behaviour when a user maps to no tenant.
- **Injection & input handling:** SQLi, XSS, SSRF, command/template injection across app & API.
- **Web app security:** OWASP Top 10, security headers, CSRF, CORS, cookie flags.
- **API security:** broken object/function-level authorisation, mass assignment, rate-limiting,
  error verbosity.
- **Secrets / information disclosure:** exposed credentials, tokens, internal endpoints,
  source maps, stack traces.

## 5. Test environment & data

- Test against the **dev/staging instance** (`dev.analytically.info`) backed by **synthetic
  test tenants only** — no real patient data is exposed to the testers.
- At least **two synthetic tenants** are provisioned so cross-tenant isolation can be
  exercised with real-but-fake data present in each.
- The Processor provisions **test accounts at each access level** (viewer, and as needed
  dev/ops) for authenticated testing. **[CONFIRM credentials handover method.]**

## 6. Rules of engagement

- Testing window and any blackout periods: **[CONFIRM].**
- Provider must **not** exfiltrate, alter or destroy data beyond what's needed to evidence a
  finding; no DoS; stop-and-report immediately on discovering any real personal data.
- Authorisation: written authorisation to test the in-scope assets will be provided
  (testing is authorised security assessment, not unauthorised access).
- Point of contact during the test: **[security contact — CONFIRM].**

## 7. Approach

**Grey-box** preferred — provide the testers with the access-control model
(`ACCESS_MODEL.md`), the architecture summary, and authenticated test credentials, so
effort focuses on the isolation/auth boundary rather than reconnaissance.

## 8. Deliverables

- A report with an executive summary and **risk-rated findings** (CVSS or equivalent), each
  with reproduction steps and remediation guidance.
- A **remediation re-test** of any High/Critical findings included in the engagement.
- An **attestation/summary letter** suitable to share with customers during due diligence.

## 9. Timing

Scheduled when the platform is **launch-ready** (to avoid re-testing after material changes)
and **before** real-tenant onboarding. Re-test after remediation; thereafter re-test on a
**[CONFIRM cadence — e.g. annual]** basis and after any significant change to the auth or
isolation boundary.

---

*Related: `DPIA.md` §12, `SECURITY_OVERVIEW.md`, `ACCESS_MODEL.md`,
`INFORMATION_SECURITY_POLICY.md`.*
