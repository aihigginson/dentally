# Guided automated onboarding — feasibility assessment

**Question:** to what extent can the Website drive a *guided, automated* onboarding for a new
Dentally practice, given we've already automated Xero connect but Dentally onboarding is manual?

**Verdict:** **Most of it is automatable, on the already-proven Xero self-serve pattern.** The
auth handoff (a "Connect Dentally" OAuth button) and the provisioning chain are high-value, low-risk
wins. The two genuine limits are (1) the **initial data backfill is a multi-hour, rate-limited job**
(not instant), so onboarding needs a "preparing your data" holding state, and (2) **Fabric
orchestration + shared capacity** need engineering to trigger per-tenant and to scale. None are
blockers; they shape the UX (async "we're getting your data ready") rather than prevent it.

## The Xero precedent (what "automated" already looks like)
`Web/app.py` `/api/xero/connect` → returns the Xero authorize URL → the practice consents on Xero's
own domain → `/api/xero/callback` exchanges the code and stores tokens in Key Vault
(`xero-tokens-<env>`). App client id/secret live in Key Vault; redirect URI registered on the Xero app.
Self-serve, in-app, tenant-admin-gated. **This is the template to copy for Dentally.**

## Onboarding surface — step by step (today → can we automate?)
| # | Step | Today (manual) | Automatable? |
|---|------|----------------|--------------|
| 1 | Sign-up / capture the practice | Marketing site enquiry form (Web3Forms) → manual follow-up | Yes — front door on the marketing site, hand to the app wizard |
| 2 | **Connect Dentally (auth)** | Paste an OAuth token into `dentally-tokens-<env>` KV secret | **Yes — mirror Connect Xero** (OAuth authorize→callback→KV). The linchpin win. |
| 3 | Connect Xero (finance, optional) | Already self-serve (`/api/xero/connect`) | **Already done** |
| 4 | Provision the access chain | Hand SQL: `Audit.Tenants` (+ Dentally creds), `Security.Clients`, `Security.Application_Users` | Yes — an onboarding service writes them. Caveats: these are per-env, out-of-git, secrets in KV; the app would need KV *set* rights. |
| 5 | **Initial data pull** | `Ingest_Dentally` notebook, run standalone; ~1.9M rows, **rate-limited 3,600/hr ⇒ multi-hour/overnight** | Trigger via Fabric REST API — but **cannot be instant**. Needs a background job + "preparing your data" status. Biggest UX constraint. |
| 6 | Build + model refresh | `Orchestrate_Build` (`run_dentally_ingest=False`, `tenants_override=[N]`) | Yes — trigger via Fabric REST API after the pull |
| 7 | RLS isolation verify (mandatory) | `Check_RLS_Isolation.ps1` | Yes — run as an automated gate before "go live" |
| 8 | Subscriptions / billing / affiliate | Owner assigns profiles in-app; `Account_Billing` (Paid_From/trial), affiliate vendor-set in SQL | Owner-assign already self-serve; Paid_From/affiliate are vendor SQL (keep) |
| 9 | dev→prod promotion | Stage-copy dance (`Promote_Tenant_Stage`) then purge dev | **Skip for self-serve** — onboard a real practice **direct to prod**; the dev-pull/copy exists only because we hand-tested Maple in dev |

## The genuine constraints (shape the UX, not blockers)
- **Dentally rate limit — 3,600 req/clock-hour.** The first pull is ~23–25k calls ⇒ ~7 hourly
  windows. Levers: (a) **ask Dentally to raise the limit for the migration** (collapses to ~1h),
  (b) parallelise across practices (each practice = its own rate bucket — see `project_ingest_scaling`).
  Either way, onboarding is **"connect now, data ready in a few hours"**, not instant.
- **Fabric orchestration.** Triggering per-tenant ingest + build + refresh needs the Fabric REST API
  (precedent exists — the delta-process work already drives pipelines via REST). Engineering, tractable.
- **Shared capacity (F2/F4).** Each new tenant adds ingest + refresh load. Onboarding at volume needs
  the ingest-scaling work (parallel across practices) + capacity headroom / autoscale.
- **Secret handling.** The app writing `dentally-tokens-<env>` means granting the app KV *set* (today
  only the pipeline identity has it). Scope tightly.
- **Confirm with Dentally:** partner OAuth **app registration** — client id/secret, redirect URI,
  scopes, PKCE. `X-OAuth-Scopes` + our existing OAuth tokens strongly imply this exists; confirm the
  partner-app mechanics before building the button.

## Where the "Website" fits
Two surfaces: the **marketing site** (`Website/`, static SWA) is the front door — sign-up captures the
practice and routes into the **authenticated app** (`Web/`), where the OAuth consent + provisioning
must happen (they need an auth context + tenant identity). So "the Website onboarding" = marketing
front door + an **app-hosted guided wizard**.

## Phased plan (recommended)
- **Phase 1 — Connect Dentally button (high value, low risk).** `/api/dentally/connect` + `/callback`
  mirroring Xero; the practice self-authorises, token lands in `dentally-tokens-<env>`. Replaces the
  manual token paste. Provisioning (step 4) can stay assisted at first.
- **Phase 2 — Onboarding wizard.** Also writes the provisioning chain (steps 4/6/7) and kicks the
  initial Fabric ingest via REST API, with a **"preparing your data (up to a few hours)"** status
  screen and a notification when ready. Direct-to-prod.
- **Phase 3 — Full self-serve from the marketing site.** Sign up → connect Dentally (+Xero) →
  subscribe/pay (Paid_From/trial already modelled) → data-ready email. Needs capacity autoscale +
  parallel ingest for volume.

## Open decisions (for the user)
1. Confirm Dentally **partner OAuth app** registration + scopes (contact Dentally).
2. Onboard real practices **direct to prod** (recommended) vs keep the dev-pull/stage-copy step.
3. Acceptable "data ready" SLA — do we pursue a raised Dentally rate limit for migrations?
4. How self-serve at launch: guided-but-vendor-assisted (Phase 1/2) vs fully self-serve (Phase 3)?
5. Billing tie-in: does the free trial clock (`Paid_From`) start at connect, at data-ready, or at
   first sign-in?

## Settled design (2026-07-17) — self-serve 30-day trial, no human step
The connect must be PUBLIC (a brand-new practice has no app login), so it lives OUTSIDE the app:
the marketing "Start your 30-day trial" CTA → `/onboarding` (a public page served by the Flask
backend). Auto-provision is safe because two gates cover authenticity + authority:
1. **Email challenge-response** — the verified address is taken as the practice **principal**.
2. **Authority attestation** — an explicit tick: "I have appropriate Dentally access and am authorised
   to share this practice's data." (patient data — the consent gate, not optional.)
3. **Dentally OAuth** — you can't provision without a real token, so there are no fake tenants.
The callback records a **pending trial** (token + details + `Paid_From = connect + 30d`) keyed by the
Dentally practice id (idempotent); the evening run provisions + pulls. The 30-day trial IS the
`Account_Billing.Paid_From` we already built.

### Built in this spike (dev, not yet pushed)
- Public page `Web/onboarding.html` (practice + email → code → attestation → Connect Dentally → done).
- Backend (public, no auth): `/onboarding`, `/api/onboarding/challenge`, `/verify`,
  `/dentally/connect`, `/dentally/callback` — stateless (HMAC-signed token per step), pending trial
  in KV `onboarding-pending-<env>`. Email send abstracted (`_send_email`; dev logs the code).
- Marketing CTA repointed to `/onboarding`. In-app Connect-Dentally button removed (wrong place).

### Abuse / capacity model
The token requirement closes anonymous abuse (no real Dentally token ⇒ no tenant). The email challenge
closes pre-OAuth spam. Residual = **capacity/cost**, managed not gated:
- **Capacity plan:** F4 at go-live → **F8 after a few signups** (expected to sit there a while) →
  then split **DEV onto its own F2**. So prod trials run on F4/F8 headroom; dev stops competing later.
- **Guardrails (to build with provisioning):** stagger/queue the evening pulls (don't fire all trials
  at once), cap concurrent active trials, per-email/domain/IP rate-limit the challenge + signup,
  dataset-size sanity check, auto-expire at day 30 (= `Paid_From`), capacity alerting.

### Remaining dependencies for a true no-human trial
- **Dentally partner OAuth app** — client id/secret in KV (`dentally-client-id`/`-secret`) + register
  redirect `https://<host>/api/onboarding/dentally/callback`; confirm authorize/token endpoints + scopes.
- **Email provider** — wire `_send_email` to ACS/SendGrid/SMTP (env-configured).
- **Auto-provision step** — the evening run reads `onboarding-pending-*` → allocates tenant/client,
  writes the access chain + `Account_Billing` (`Paid_From`), moves the token to `dentally-tokens-*`,
  kicks `Ingest_Dentally`. (This spike stops at "pending trial captured".)
- **External login identity** — the app is MSAL/Azure AD; a self-serve practice email needs Azure AD
  External Identities / B2C so the principal can actually sign in post-onboarding.

## Auto-provision step (BUILT + proven on dev, 2026-07-17)
`Audit.usp_Provision_Tenant` (@Practice_Name, @Principal_Email, @Paid_From, @Dentally_Practice_ID,
@Access_From, @Tenant_ID OUT) — the DB core of provisioning:
- allocates a new id (Tenant_ID == Client_ID, MAX+1 across both tables) — real practices are 100+,
- writes the access chain: `Security.Clients`, `Audit.Tenants` (API creds NULL -- token lives in KV),
  `Security.Application_Users` (principal on the **Full** profile + Maintain_Targets),
- writes the trial billing: `Billing.Account_Billing` (`Paid_From` = access + 30d) + `Security.Access_Log`,
- **idempotent on the principal email** (a re-run returns the existing tenant, no duplicates).
Proven: provisioned a throwaway practice -> full chain created -> re-run returned same tenant -> cleaned up.

### Remaining glue (the orchestrator + the first-pull)
1. **Orchestrator** (Fabric notebook or script, runs on the evening cadence): read KV
   `onboarding-pending-<env>` -> for each `pending_provision`: `EXEC Audit.usp_Provision_Tenant` ->
   move its `oauth` token into KV `dentally-tokens-<env>[<Tenant_ID>]` ({token, base_url, name, oauth})
   -> set the pending record `status='provisioned'` + the allocated `tenant_id`.
2. **Initial ingest** — the one genuinely hard bit: the first Dentally pull is **multi-hour**, so it
   **can't ride Orchestrate_Build's 1-hour ingest cell** (per DENTALLY_ONBOARDING). Options: trigger a
   **standalone Fabric notebook job via the REST API** (no child timeout), or a **capped initial pull**
   (recent slice) then backfill. Decision needed. After the first pull, nightly incrementals ride
   Orchestrate normally.
3. **Token refresh** — Dentally OAuth tokens expire; `Ingest_Dentally` must refresh via the stored
   `oauth.refresh_token` and persist back to KV (mirrors how Ingest_Xero refreshes).

## External login identity (investigated 2026-07-18) — mostly already solved
**Headline: the app is already a MULTI-TENANT Azure AD app**, so most practices need NO new identity
infrastructure. Evidence in `Web/`:
- Frontend MSAL `authority: …/common`, scopes `['openid','profile','email']` (basic OIDC — **user-
  consentable, no admin consent** needed for a new org).
- Backend `_validate_id_token`: JWKS from `/common`, checks signature + `audience=CLIENT_ID` + expiry
  but **`verify_iss=False`** → a token from **any** Azure AD tenant is accepted.
- Authorization is the `Security.Application_Users` allowlist, **fail-closed** (unprovisioned UPN → 403).

**So:**
1. **M365 / Azure-AD practices** (a large share of UK dental) — the principal's work email *is* an Azure
   AD identity. They can **sign in today** via `/common`; auto-provision writes `Application_Users.User_UPN
   = their email` and they're straight in. **Zero new identity infra.**
2. **Personal Microsoft accounts** (outlook.com/hotmail) — covered too if the app registration allows
   personal accounts (the model already contains `aihigginson@outlook.com`, which implies it does).
3. **The only gap = non-Microsoft emails** (Google Workspace, other) — not Azure AD, so `/common` can't
   authenticate them. Those need a CIAM: **Microsoft Entra External ID** (successor to Azure AD B2C) — a
   separate external tenant where anyone signs up with email+password or Google, issuing tokens the app
   trusts (issuer is already skipped; just add its authority to the frontend, validate its audience, and
   ensure the email claim matches the provisioned `User_UPN`).

**Recommendation (phased):**
- **v1 (now, ~no new infra):** lean on the existing multi-tenant Azure AD. Onboarding already verifies the
  principal's email; sign-in copy = "use your Microsoft 365 account." Optionally detect at onboarding
  whether the email is Microsoft-backed and message accordingly. Launch M365-first — it covers a big slice.
- **v2 (later):** add **Entra External ID** as a second sign-in path for non-Microsoft practices.

**Confirm:** app registration "supported account types" = multi-tenant (+ personal if wanted); and that
`preferred_username` (the claim mapped to the UPN) equals the provisioned `User_UPN` for a normal M365 user
(it does). Note: because issuer isn't verified, the `Application_Users` allowlist is the *only* gate — so
provisioning the exact UPN is critical, and de-provisioning removes access. That's already the design.
