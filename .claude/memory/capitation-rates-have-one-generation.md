---
name: capitation-rates-have-one-generation
description: "Maple's capitation rates are all back-dated to 2020, so history is priced at today's rates; the real Xero gap after that is ~1.5% non-paying members."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-12T12:33:58.559Z
---

Craig's `Input.Plan_Capitation_Rate` figures for tenant 100 are **net** — Denplan's handling fee
is already removed — so a Xero-vs-capitation comparison has the fee out of both sides. The fee is
never the explanation for a gap.

All eight Maple rate rows carry `Effective_From_Date = 2020-04-01` (one, 2020-01-01), entered
2026-10-07. One generation. The loader is correct — `Gold.usp_Load_Fact_Revenue.StoredProcedure.sql:372`
takes the latest rate effective on or before the month — there is simply nothing earlier to pick,
so six years of history is priced at 2026 rates.

Measured 2026-10-12, Denplan receipts (identified by `Silver.Xero_Finance_Lines.Contact_Name =
'Denplan'`, NOT by account code — Maple posts all income to `4000 Sales`) against
`Gold.Fact_Revenue_Capitation`: our £/head is flat ~£36.3 across 20 months while Xero's climbs
£30.9 → £33.4 → £36.0, about 8%/yr — Denplan's annual April rises. The gap closes to ~1% exactly
when the real rate catches up with the entered one.

**Why:** the headline 5.5% 12-month gap is mostly stale rates, not a data defect and not a fee.
Once the rates are right the residual is ~1.0-1.7% (~20 members) — patients Dentally marks active
on a plan who are no longer paying. Dentally exposes an active plan and no payment status, so
capitation is structurally an UPPER BOUND. Plan switchers sit on their current plan, re-pricing
their history, but £/head drifts down over time so that bias looks minor.

**How to apply:** before reading any capitation gap as a defect, check how many rate generations
the tenant has. The fix is owner data entry, not code. Extends
[[capitation-is-an-estimate-not-observed-income]] and [[who-counts-as-a-plan-patient]].
