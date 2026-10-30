---
name: skeleton-tenants-have-no-date-spine
description: "Skeleton Group (client 20, tenants 21-24) can never render a report — too few appointments for a date grouping."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-30T12:30:06.961Z
---

Skeleton Group — client 20, tenants 21–24 — is **structure without volume**. It has sites,
practitioners, a ragged five-level hierarchy and ~800 Fact_Metric_Actuals rows each, but only about
twenty appointments per tenant in total.

`Gold.usp_Load_Dim_Date_Grouping` only builds a date spine for a tenant with **100+ appointments in
a financial year**. Tenants 21–24 clear that in no year, so they have no `Gold.Dim_Date_Grouping`
rows, therefore no `Gold.Aggregate_Period_Targets` rows, therefore nothing renders for them on any
report page — not targets, not actuals.

**Why:** it looks like a targets or RLS fault when a perfectly correct `Fact_Node_Targets` produces
an empty home page. It is neither.

**How to apply:** use Skeleton Group to test hierarchy SHAPE (folding, node keys, the Targets
data-entry screens, warehouse arithmetic). Use **client 11** when something has to be seen on a
report — it is the only client with both a multi-level hierarchy and real volume. Making client 20
renderable means generating appointments for four tenants, which is a seeding job, not a config
change; see [[batch-generator-changes-before-reseeding]].
