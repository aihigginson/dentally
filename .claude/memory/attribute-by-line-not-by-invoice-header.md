---
name: attribute-by-line-not-by-invoice-header
description: "OPEN with Craig: whose work is it? Revenue is already line-attributed; the invoice-level measures are header-attributed, and the discount line already names its own practitioner."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-07T11:41:05.057Z
---

**SETTLED 2026-10-07: LINE LEVEL.** The owner checked with Craig and confirmed it — the money
belongs to whoever did the work, not to whoever heads the invoice. The discount measures now read
`_Revenue Invoice`. The question as originally posed: when an invoice
spans two practitioners, who does the money belong to? His instinct — *"line level because that is
who has done the work"* — and he expects it to affect more than discounts: *"it probably affects all
attribution I've just not thought about it before."*

**What is already true, measured on prod:**

* `Total Revenue` sums `'_Revenue'`, which keeps the **per-line** practitioner. So revenue,
  contribution and £/hour already follow the work. **Line attribution is the existing convention.**
* `Gold.Fact_Invoices` picks **one** practitioner per invoice ("prefer dentist/ortho/specialist,
  else any"), so the invoice-level measures — discounts, deposits, debt, outstanding — are
  **header**-attributed and are the odd one out.
* Scale: **8,765 of 50,934 invoices (17%) and £1,356,071 of £7.55m (18%)** have lines from more than
  one practitioner. Not an edge case.
* **Every discount line carries its own practitioner — 655 of 655, no nulls.** So for discounts
  there is nothing to apportion and no double-counting: one line, one practitioner, additive. On
  multi-practitioner invoices it routinely differs from the header (invoice 63465373: discount line
  Craig Jack, header David Mason, £580).
* Of 643 discounted invoices: 631 have one discount line, 10 have several from the same
  practitioner, and **2 have discount lines from different practitioners** — so invoice grain very
  nearly holds but not quite, and `Gold.Invoice_Discount` would need line grain to be exact.

**How to apply:** do not quietly pick a side. `Patients With Discount` was moved to header
attribution purely to stop the summary and its own drill-through disagreeing (bar 3, detail 2); that
was a consistency fix, not a ruling on attribution, and it under-reports whoever worked a line of
someone else's invoice. Related: [[a-detail-table-needs-a-column-not-a-measure]],
[[discounts-are-negative-invoice-items]].
