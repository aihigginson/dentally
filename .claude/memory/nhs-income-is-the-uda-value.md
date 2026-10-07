---
name: nhs-income-is-the-uda-value
description: NHS revenue is UDAs delivered at the contract rate; the patient's band charge is a slice of that same value, not income on top of it.
metadata:
  type: project
---

What a practice earns for an NHS course is **its UDAs at the contract rate**. A band 2 course
worth £90 with a £20 patient charge earns £90: the patient funds £20 and the NHS supplies £70.
Which half arrives from whom is a cash-flow matter between the patient and the NHS and says
nothing about what was earned.

**Why:** until V197 (2026-09-28) `[NHS Revenue]` summed invoice lines where `NHS_Charge > 0` —
the patient's slice alone. For Maple that was £3,641 against £118,796 of contract work, about
three percent. The two figures can never be added: the charge is *inside* the UDA value, so
counting both double-counts the patient's share. `Gold.usp_Load_Fact_Revenue` now drops NHS
invoice lines and writes `Revenue_Type = 'NHS'` rows at the rate from
`Gold.Dim_NHS_Contracts.UDA_Value` (£32.72 for Maple), using `COALESCE(Awarded_UDA,
Expected_UDA)` — the same basis `[NHS UDA Delivered]` uses — and excluding `'invalid'` and
`'withdrawn'` claims in lower case, because the collation is BIN2.

**How to apply:** sanity-check any NHS revenue figure against UDAs × rate before believing it,
and cross-check UDA counts two ways — delivered against the contract target should reproduce the
UDA completion percentage the NHS page shows, and FY-to-date should be a sensible fraction of the
rolling year. Note `[NHS UDA Delivered]` is deliberately financial-year scoped
(`REMOVEFILTERS('List Date')`), so it does NOT answer "last 12 months" — reading it as though it
did understated the annual figure by half. Related:
[[capitation-is-an-estimate-not-observed-income]], [[fabric-collation-is-case-sensitive]].
