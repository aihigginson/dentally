---
name: dev-targets-are-dummy-prod-targets-are-real
description: Target values in DEV are deliberately made-up; the real ones live in PROD and were agreed with the customer.
metadata:
  type: project
---

Target values differ between environments **on purpose**. DEV holds dummy numbers the owner
entered to exercise the model; PROD holds real targets worked out with Craig at Maple. They have
never matched and are not meant to.

**Why:** a DEV/PROD target comparison looks alarming and means nothing — e.g. Maple's Last 3
Months total revenue target is £249,042 in DEV and £498,084 in PROD, and in DEV the total and
private targets happen to be equal. On 2026-09-28 I offered that gap as evidence that DEV's
targets had been reset by the generator. It was not evidence of anything.

**How to apply:** never use PROD targets as the expected value for a DEV check, or the reverse.
To verify a change to target logic, compare DEV against DEV — `SUM` vs `MAX` out of
`Gold.Aggregate_Period_Targets` for the same grouping reproduces the board to the pound. Related:
[[verify-aggregation-changes-on-two-tenants]], [[calibrate-the-demo-tenant-against-live]].
