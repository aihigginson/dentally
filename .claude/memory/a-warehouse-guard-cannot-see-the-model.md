---
name: a-warehouse-guard-cannot-see-the-model
description: "V224 proved no SQL module read two PBI views, dropped them, and broke the semantic model for months -- the model is not a SQL module."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-22T11:43:16.176Z
---

V224 dropped `PBI.[_Targets]`, `PBI.[_Effective Targets]`, `Gold.Fact_Targets` and
`Gold.Fact_Effective_Targets` as dead. Its guard was:

    SELECT COUNT(*) FROM sys.sql_modules m ... WHERE m.definition LIKE '%Fact[_]Targets%'

which proves only that **no stored procedure or view** references them. The **semantic model
is not a SQL module**, and it still had Power Query queries bound to both views. They have
read "The key didn't match any rows in the table" on DEV and PROD ever since, surfacing only
when the owner next opened the model in Desktop. The replacement chain
(`Fact_Daily_Targets` -> `PBI.[_Daily Targets]`, `Aggregate_Period_Targets` ->
`PBI.[Aggregate Period Targets]`) was fine throughout, so nothing in the product broke and
nothing alerted.

Related: `Meta.usp_Create_Gold_Views` **drops every view in the PBI schema** and recreates
only what Gold tables and `Gold.vw_*` views generate. So a hand-written PBI view cannot
survive -- that is how `PBI.[Security Users]` disappeared (harmlessly; RLS had already moved
to `PBI.[Application Users]` over `Security.vw_User_Tenant_Access`). Never answer a problem
with a bespoke PBI view.

**Why:** the warehouse has no visibility of its only consumer. A dependency check inside
SQL is necessary and never sufficient.

**How to apply:** before dropping or renaming anything in the PBI schema, the model must be
checked by hand -- no guard can do it. Prefer leaving a superseded view in place over
dropping it; an unused view costs nothing and a missing one breaks a refresh silently.
Related: [[changing-a-fact-means-sweeping-its-derivations]],
[[a-vw-override-silently-drops-new-columns]], [[a-new-model-table-has-no-rls]],
[[nightly-model-refresh-reports-false-success]].
