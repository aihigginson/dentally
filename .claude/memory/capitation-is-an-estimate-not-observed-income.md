---
name: capitation-is-an-estimate-not-observed-income
description: "All plan/capitation revenue is reconstructed from clinical evidence - the real figures are in the plan provider's spreadsheets, which the warehouse has never seen."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T10:15:31.516Z
---

Membership income is collected by the **plan provider** — Denplan, Tabeo, or whoever the
practice uses — and the authoritative figures are in the spreadsheets that provider sends the
practice. Dentally holds no invoice, no payment and no statement for any of it, so every
capitation figure in the warehouse is **reconstructed**: a completed, non-charged Exam/Hygiene
course is taken as evidence of membership that month, priced from the owner-curated
`Input.Plan_Capitation_Rate` and spread across the month's working days.

Four assumptions sit in that chain, any of which can be wrong for a given patient: a free exam
may be goodwill or a stale plan flag; providers discount and change rates mid-term; an active
plan flag survives a failed direct debit; and gaps between exams are bridged deliberately.

**Why:** the user corrected me on 2026-09-27 — *"these are guesses not real things… The real
numbers are held in spreadsheets produced by denplan or tabeo or whoever is their plan
provider."* I had been describing capitation totals as though they were observed income, and
I had also mischaracterised `Is_Estimated_Plan`.

**`Is_Estimated_Plan` IS CORRECTLY NAMED. LEAVE IT.** It flags the rows where the warehouse
genuinely guessed the patient was on a plan rather than reading a status. The owner confirmed
this on 2026-09-29 and asked to stop being reminded; I had twice listed a rename as outstanding
work on the belief that the name was misleading. It is not.

**==> DO NOT PROPOSE LOADING THE PROVIDER STATEMENTS. THAT IS WHY THE ESTIMATE EXISTS. <==**
The owner ruled this out on 2026-09-28: *"Provider statements are a joke. Different formats each
month which is why we've gone the route of estimation."* Estimation is the deliberate answer to
an unparseable source, not a stopgap waiting for the real data. I had listed statement-loading as
outstanding work; it is not work, it is a closed decision.

**How to apply:** never present capitation as collected income, reconcile it to a bank figure,
or put it in front of an accountant — it is right for trend, plan mix and per-patient value.
Total Revenue is part-actual, part-estimate for the same reason. V191 says so in the category
string, the in-product glossary and the measure descriptions. Related:
[[never-deploy-an-input-table-in-a-release]], [[dont-re-raise-settled-decisions]].
