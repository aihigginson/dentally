---
name: sales-monitor-shape-and-deferred-card-stages
description: "The sales monitor's layering (Sales.* detail -> Gold dims/fact -> PBI Affiliates), and why the two Stripe card stages are deliberately unimplemented."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-02T19:11:54.799Z
---

Built 2026-10-02. One place for: verification emails sent, keys set up, card supplied, card used,
and product usage.

        Web/sales_monitor.py        lands the non-SQL sources into Sales.*
        Sales.Usage_Daily           (App_Env, Tenant, login, day) + embeds that day
        Sales.Funnel_Event          one row per funnel stage reached
        Gold.Dim_Client             one row per COMPANY, prospects included, + the -1 member
        Gold.Dim_Sales_Status       16 states; Funnel and Access roles; Is_Gap as DATA
        Gold.Fact_Client_Status     ONE ROW PER CLIENT
        caj-sales-monitor-<env>     daily 06:40 UTC
        GOLD_DIM_DATE -> GOLD_DIM_CLIENT -> GOLD_FACT_CLIENT_STATUS   in the nightly DAG

**==> PBI Affiliates, NEVER PBI Dentally. <==** It holds prospect emails and which practice has
gone quiet. Note the control is **absence from the MODEL, not absence of the view** — the PBI views
exist (`List Client`, `List Sales Status`, `_Client Status`), exactly as the affiliate ones do.
Add the status dimension TWICE as role-playing copies: the fact has two fks to it and only one
relationship can be active.

**==> THE CARD STAGES ARE DELIBERATELY NOT IMPLEMENTED. DO NOT BUILD THEM SPECULATIVELY. <==**
`card_attached` and `card_chargeable` exist in `Dim_Sales_Status` and are never populated.
Confirmed with the owner on 2026-10-02: leave them until a real card exists. There is nothing to
test against — no `Account_Billing` row has a `Stripe_Customer_ID`, no trial has reached the token
step, `Billing.Stripe_Invoice` is empty, and Maple is free-forever (`Paid_From = 2100-01-01`).
The distinction matters and must be verified, not assumed: setup-mode Checkout only ATTACHES a
card, so a customer can hold a good one with no `invoice_settings.default_payment_method` and fail
to bill (see `Web/app.py` ~2550, which already adopts the attached card).

**How to apply:** two rules this cost real bugs to learn. **`Is_Vendor` beats the client mapping** —
our support accounts are provisioned AS customer users (prod `admin@` and `grace@` carry
`Client_ID = 100`), so attributing by `Application_Users.Client_ID` credited 2,309 of our report
opens to Maple and reported a 22-day-dormant customer as "Active". And **the loader must only
delete the window it reloads** — deleting all of it cut prod from 53 rows to 20 and would have made
the dormant customer read "never accessed" once past 30 days. Related:
[[a-report-render-costs-about-27-cu-seconds]], [[affiliate-commission-never-in-the-customer-model]],
[[onboarding-is-manual-by-choice]].
