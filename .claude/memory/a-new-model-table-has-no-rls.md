---
name: a-new-model-table-has-no-rls
description: RLS in the PBI model is written per table, so a table added later needs its own rule - check, do not assume either way.
metadata:
  type: project
---

RLS in `PBI Dentally` is **per table**: every tenant-bearing table carries its own filter on
`[Tenant ID]` against `Application Users`. Nothing propagates a rule to a table added afterwards,
and nothing warns when one is missing.

**Why:** this matters most when a measure SUMs the table — as the target measures do — because an
unfiltered table would add every tenant's rows into a single practice's figure. Dev has only two
tenants and the admin login sees both, so no row count or total can reveal a missing rule there;
prod has many. When `Gold.Aggregate_Period_Targets` was added in V196 the owner added its rule at
the same time, so it was filtered — I asserted it probably wasn't, on the Get Data reasoning
alone, after two attempts to verify had failed. The reasoning was sound and the conclusion was
unfounded: state "cannot determine" rather than a likelihood.

**How to apply:** add the rule in the same change as the table. `Fabric/PBI_Dentally.csx` ends
with a block that guarantees it, copying the filter from whichever table already has one (so it
tracks the real rule, `CUSTOMDATA()` scoping included) and logging `already filtered` /
`filter ADDED` / a loud `LEFT UNFILTERED` — extend the table name there rather than hand-typing a
duplicate, and read the log. Two ways to check do NOT work from here: XMLA with an az CLI token
fails `Authentication failed for all authenticators`, and `executeQueries` with
`impersonatedUserName` is refused `RLSNotAuthorizedForModel`. Related:
[[verify-aggregation-changes-on-two-tenants]].
