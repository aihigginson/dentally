---
name: payment-allocations-has-never-ingested
description: Bronze/Silver Payment_Allocations is empty for every tenant, so cash cannot be attributed by line.
metadata:
  type: project
---

`Bronze.Payment_Allocations` and `Silver.Payment_Allocations` hold **zero rows for every
tenant**, and always have. The nightly Bronze and Silver loaders run and log SUCCEEDED
with 0 rows (checked 17-19 Oct 2026), and `payment_allocations` never appears in
`Audit.Ingest_Log` at all, so nothing is landing for them to merge.

The code looks healthy, which is why this is worth remembering: the entity is in the
extractor list (`API/seed_bronze.py`), and both `BRONZE_PAYMENT_ALLOCATIONS` and
`SILVER_PAYMENT_ALLOCATIONS` are registered in `Audit.Process_Config`. Only the data is
missing.

`Silver.Payment_Explanations` IS current (newest row 2026-10-19, payments to 19 Oct), but
it ties a payment to an **invoice**, not to an invoice item.

**Why:** allocations are the only line-level tie from a payment to an invoice item. Without
them, cash received cannot be attributed to a practitioner except pro-rata across an
invoice -- and Maple's invoices routinely carry several practitioners' work, so pro-rata is
an approximation, not a reconciliation.

**How to apply:** any question about money *received* per practitioner is currently
unanswerable at line level -- say so rather than presenting a pro-rata split as exact. See
[[attribute-by-line-not-by-invoice-header]] and
[[never-infer-a-write-succeeded-from-a-wrapper]]; a SUCCEEDED proc with 0 rows is the same
class of false comfort.
