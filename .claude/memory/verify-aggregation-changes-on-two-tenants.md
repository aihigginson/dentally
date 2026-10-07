---
name: verify-aggregation-changes-on-two-tenants
description: SUM and MAX agree on a single row, so any change to an aggregator must be checked against a login that sees more than one practice.
metadata:
  type: feedback
---

A precomputed aggregate at one row per (tenant, grouping, metric, level) makes `SUM` and `MAX`
**identical for a single-practice login** and different for a group. Checking one practice proves
nothing about either.

**Why:** V196 collapsed all eight DAX target builders to one `MAX('Aggregate Period Targets'
[Target Value])`, reasoning that the table had already chosen the right value per metric. It had
— per tenant. On "All practices" every cumulative tile silently dropped by one practice's worth
(total revenue £697K → £448K) while every rate tile was unmoved, because rates were `MAX(Annual)`
before and after. The user spotted it from the board and named the cause before I did.

**How to apply:** when a target or aggregate changes, read the before/after straight out of
`Gold.Aggregate_Period_Targets` as `SUM(...)` vs `MAX(...)` grouped by metric across both tenants
— that table is small and reproduces the board's numbers to the pound, which is faster and surer
than a model query. The split to preserve is `Config.Metric_Definitions.Target_Type`: cumulative
accumulates and so must SUM across practices; rate and point_in_time are thresholds and must MAX.
Related: [[a-new-model-table-has-no-rls]], [[calibrate-the-demo-tenant-against-live]].
