# Launch plan — ~4 working weeks (6 cal weeks minus holidays)

**Goal:** onboard + charge real dental practices.

## The one decision that de-risks everything: launch CONCIERGE, not self-serve
For the first cohort WE onboard each practice by hand: they give us Dentally access via a **personal
access token** (no partner OAuth app needed), we provision (`Audit.usp_Provision_Tenant`, built) and
kick the first pull. This takes the two biggest unknowns OFF the launch critical path:
- **Dentally partner-app approval** — external, unknown timeline; not needed for concierge.
- **Fully-automated multi-hour first-pull** — we run it per practice, overnight.
The public self-serve flow (Connect-Dentally OAuth + auto-provision + first-pull automation) — already
largely built/designed — becomes a **fast-follow after launch**.

## Critical path — must-have to launch
| Owner | Item | State |
|---|---|---|
| **You** | **PBI reports** — the actual product / value | in progress (the true gate) |
| **You** | Create the **Stripe** account + drop keys in Key Vault | to do |
| **You** | Chase Dentally: raise the **migration rate limit**; partner creds (for self-serve later) | to do |
| **Me** | **Concierge onboarding runbook** — provision (done) + wire the first pull per practice | build |
| **Me** | **Stripe** integration (trial→paid; the 30-day trial buys time, can land just after launch) | build (after your account) |
| **Me** | **Prod cutover** of everything built on dev (billing #1/#2, trial banner, contact, onboarding, provision SP) — consolidated manifest + AppDB promote + app PR | build |
| **Me** | **End-to-end pilot** — one real practice through the concierge flow on PROD | test |

## Can slip to fast-follow (NOT launch blockers)
- Public self-serve onboarding + Connect-Dentally OAuth (waits on Dentally partner creds)
- First-pull automation; PDF invoice (#3 — send a manual invoice for the first few)
- AI signup bot; Entra External ID (M365 practices already sign in); Phase-B branded sender; in-app tour/videos

## Biggest risks
1. **PBI reports** — the product itself; your focus, and the real gate.
2. **Dentally rate limit** on first pulls — get it raised, else stagger overnight (fine for a handful).
3. **Prod cutover** — a good chunk of the billing/onboarding work is dev-only; needs promoting cleanly.
4. **Capacity** — F4→F8 as signups grow (already your plan).

## What I start on now (no external deps)
1. **Concierge onboarding wiring** — the orchestrator glue (pending/token → provision → kick pull) so I
   can onboard a practice end-to-end from a personal token.
2. **Prod cutover** of the dev work (so the paid product actually exists on prod).
3. **Stripe** — the moment your account + keys exist.
(#3 PDF invoice fits in once the above land.)
