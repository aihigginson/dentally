---
name: calibrate-the-demo-tenant-against-live
description: Judge generated demo data by querying tenant 100, not by what looks plausible.
metadata:
  type: feedback
---

The demo tenant (11, Valley Dental Group, dev only) is only credible if its numbers are
measured against the live practice — tenant 100 — rather than guessed at. Every serious
fault in it was invisible to inspection and obvious to a comparison query:

- 0.7% cancellations against a real **26%**. A real diary is a quarter cancel-and-rebook.
- appointment states `booked` / `did_not_attend` where Dentally emits `Pending` / `Did not attend`.
- 100% of patients missing a date of birth, against 0% live.
- every retention route populated except `Cancelled Not Rebooked`, which sat at zero.
- `short_notice_cancellation_rate` at 100% against 17%.

**Why:** the generator's rates were invented, and plausible-looking invented numbers are
wrong by factors of 30 without ever looking odd. A practice where nothing goes wrong also
makes every recovery feature in the product look pointless.

**How to apply:** before changing a generator rate, query tenant 100 for the same figure over
the same window, filtering `fk_Patient > 0` to exclude the lunchtime blocking-out rows. When
a rate produces *extra* rows rather than re-labelling existing ones, solve it backwards —
26% cancelled needs a clone probability of 0.36, not 0.26. Note that ordering inside
`generate_tenant` is load-bearing: `_add_disruption` must run after invoices and treatment
plans (which must not see cancellations) but before `gen_patient_stats` (which must).
See [[t11-is-both-demo-and-regression-fixture]].
