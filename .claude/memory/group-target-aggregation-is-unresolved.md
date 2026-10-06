---
name: group-target-aggregation-is-unresolved
description: How targets combine across practices is only settled for cumulative metrics; rates and point-in-time take the max, which is deferred until a real multi-practice client exists.
metadata:
  type: project
---

A login that sees more than one practice combines each target family differently, and only one of
the three is deliberate:

- **cumulative** — SUM across practices. Correct: two practices' revenue targets add.
- **rate** — MAX across practices. Questionable: a group's diary-fill target should be a
  weighted average, not whichever practice aims highest.
- **point_in_time** — MAX across practices. Probably wrong: a group's active-patient target
  should be the sum.

**Why:** deferred deliberately on 2026-09-28. No customer is affected — every customer login sees
a single practice, where all three collapse to the same number. The only two-practice login is the
owner's own (Maple + the demo tenant), which is not a real group. The rate and point-in-time
behaviour predates V196; V196 only restored SUM for cumulative after briefly making it MAX too.

**How to apply:** do not re-raise this until there is a genuine multi-practice client. When there
is, the likely shape is a `Group_Aggregation` column beside `Target_Type` in
`Config.Metric_Definitions`, resolved in `Gold.usp_Load_Aggregate_Period_Targets` or in the
lookup — not more DAX. Related: [[verify-aggregation-changes-on-two-tenants]],
[[dont-re-raise-settled-decisions]].
