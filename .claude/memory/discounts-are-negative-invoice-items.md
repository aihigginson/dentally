---
name: discounts-are-negative-invoice-items
description: "Maple DOES discount — as a negative invoice item named 'Discount' — and the warehouse rule looks for the wrong shape, so it detects none of them."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-06T11:28:22.291Z
---

**This replaces an earlier memory that said "Maple uses no discounts; zero is not a bug to hunt."
That was wrong.** Craig said on 2026-10-05 that they do discount, "done as items", and the data
agrees: **654 lines named `Discount`, −£88,350 all-time, ~£15k a year, every year since 2021.**

**The shape.** A discount is a NEGATIVE LINE ITEM on the invoice, named exactly `Discount`:

        Invisalign Final appointment   1000.00
        Invisalign aligner fit            0.00
        Discount                       -175.00
        -------------------------------------
        header Amount                   825.00  = SUM(lines)

**Why nothing detects it.** `Gold.usp_Load_Dim_Invoices` rebuilds `Gold.Invoice_Discount` with
`HAVING MAX(inv.Amount) > SUM(ii.Total_Price)` — header exceeds the lines. A negative line is
already INSIDE that sum, so header equals lines and the test is false. Measured: of 650 Maple
invoices carrying a `Discount` item, the rule flags **0**. Every one of the 2,710 rows in
`Gold.Invoice_Discount` is tenant 11 — the generator invents the header-exceeds-lines shape that
real Dentally never produces, which is exactly why the metric looked untested.

**==> A NEGATIVE ITEM IS NOT AUTOMATICALLY A DISCOUNT. <==** 981 negative items exist; only 654 are
discounts. The rest are different things and must not be counted as price reductions:
`Balance imported from Exact` (261 lines, **−£58,148** — a one-off migration artefact from the
previous PMS), `bad debt`/`Bad Debt`, `Adjust…` corrections ("pt was exempt", "should of been band
1"), and `Refund`. Treating "negative = discount" overstates discounting by about £58k.

**How to apply:** match on `Name = 'Discount'` (case-sensitive — the collation is BIN2), not on
sign. The real figures to sanity-check any fix against: **1.1–1.35% of gross invoiced items**,
rising average (£96 in 2021 → £161 in 2026), ~100–140 a year. Craig gives the largest himself —
45 in 24 months averaging £313, double anyone else. Related:
[[fabric-collation-is-case-sensitive]], [[calibrate-the-demo-tenant-against-live]],
[[t11-is-both-demo-and-regression-fixture]].
