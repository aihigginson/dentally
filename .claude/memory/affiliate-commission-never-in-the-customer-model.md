---
name: affiliate-commission-never-in-the-customer-model
description: "Affiliate commission is vendor money and must never appear in the PBI schema or the 'PBI Dentally' model, with no RLS, ever. Its own standalone model, shared with nobody."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-24T06:28:11.978Z
---

**Affiliate commission never goes in `PBI Dentally`, and never gets RLS.** Stated emphatically by
the user on 2026-09-24: *"NO RLS NOT IN PBI DEntally at any time in the future."* Treat this as a
standing constraint, not a preference to re-weigh.

It is **vendor money** — what Analytically pays a referral partner for introducing a practice. It
is not the practice's data, and it is not the affiliate's view of other practices. A practice
owner seeing what an introducer earns from them, or an affiliate seeing a practice they did not
introduce, is a breach of confidence no feature justifies.

Where it lives: `Billing.vw_Affiliate_Commission` and `Billing.vw_Affiliate_Payout` (V181), read
by **its own small standalone semantic model** in the Fabric workspace, shared with nobody.

**Why this is easy to get wrong by accident rather than by decision:**

- **`PBI.*` views are generated.** `Meta.usp_Create_Gold_Views` sweeps the whole Gold schema into
  the PBI schema. Billing is out of its reach today because it filters `s.name = 'Gold'` — so the
  protection is structural, not conventional. Moving one of these views into Gold, or widening
  that filter, would publish vendor money to customers with nobody choosing to.
- **RLS is not the control; absence is.** These views carry `Tenant_ID`, so
  `Check_RLS_Coverage.ps1` would happily PASS them once imported — they would look correctly
  secured while being entirely the wrong data in the wrong place. Never "solve" this by adding an
  RLS filter.

**How to apply:** run `Scripts/Check_Vendor_Data_Isolation.ps1` after anything that touches the
PBI layer or the semantic model. It fails on any affiliate/commission/payout/introducer name in
the `PBI` schema of either warehouse, and on any such table in the dev model. Verified to fail,
not just to pass: a deliberate leak was planted on dev, detected, and removed. The prod model
cannot be checked (the Test Runner SP is dev-only), so prod rests on the deployment pipeline
promoting a clean dev model — see [[prod-warehouse-deploy-needs-a-token]].
