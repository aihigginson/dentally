---
name: a-vw-override-silently-drops-new-columns
description: "Meta.usp_Create_Gold_Views prefers vw_<X> over table <X>, and those views list columns explicitly — add a column to the table alone and it never reaches PBI, with no error."
metadata:
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-29T16:13:13.245Z
---

`Meta.usp_Create_Gold_Views` prefers a `Gold.vw_<X>` over the table `<X>`. Those override views
pass an **explicit column list** — they exist to ADD something (`vw_Dim_Patients` adds
`Effectively_Active`, `vw_Dim_Practitioners` likewise) and they enumerate the rest by hand.

**So adding a column to the table is only half the job.** V216 added three dates to
`Gold.Dim_Patients`, deployed clean, every guard green — and `PBI.[List Patients]` came back with
its original 52 columns. No error, no warning, nothing in the log. The columns were in Gold and
stopped there.

**Why it bites later, not now:** a report bound to a field the view does not expose is a broken
visual at the practice, discovered by the customer, not a failed deploy on the laptop.

**How to apply:** when a release adds a column to a Gold table, check
`Fabric/Gold.vw_<table>.View.sql` for an override before writing the manifest, and put the column
in both. Then guard it — assert the column is present in `INFORMATION_SCHEMA.COLUMNS` for
`TABLE_SCHEMA='PBI'` under its presentation name (underscores become spaces), the way V216's guards
8 and 9 do. Known overrides: `vw_Dim_Patients`, `vw_Dim_Practitioners` — grep `Fabric/Gold.vw_*`
rather than trusting this list.

==> **IT IS NOT ONLY THE `vw_` OVERRIDES. EVERY PBI VIEW PINS ITS COLUMNS AT CREATE TIME.** <==
The generator builds an explicit `[col] AS [col]` list from `sys.columns` as it runs, so even an
auto-generated view is a snapshot. **Add or drop a Gold column and re-run the generator, every
time** — the view does not follow the table.

**The failure mode that cost an hour on 2026-10-29:** `Gold.Aggregate_Period_Targets` gained
`Tenant_ID` (the RLS access stamp) AFTER the views were last generated, so
`PBI.[Aggregate Period Targets]` still exposed `Client ID` and no `Tenant ID`. Re-reading the
table in Desktop then produced:

> Some security filter expressions have errors

…naming **no table and no role**, because the copied rule referenced `[Tenant ID]` on a table that
no longer had it. The table itself refreshed perfectly; only the rule was unbound. Order that
works: deploy the Gold change → `EXEC Meta.usp_Create_Gold_Views` → re-read in Desktop.

`Scripts/Find_Broken_RLS.csx` (Tabular Editor → Advanced Scripting) checks every role × table
expression's column references against the model and names the broken one. It also lists any
table carrying `Tenant ID`/`Client ID` with no rule in any role — which Desktop never reports,
because an open door is not an error.

Related: [[changing-a-fact-means-sweeping-its-derivations]], [[read-the-schema-before-querying-it]],
[[a-new-model-table-has-no-rls]], [[a-warehouse-guard-cannot-see-the-model]].
