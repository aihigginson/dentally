---
name: the-model-is-one-artifact
description: "A proc-level dependency check cannot clear a release — promoting PBI Dentally carries every table's column expectations."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-30T20:07:12.095Z
---

Promoting `PBI Dentally` through the Fabric `DEV TO PROD` pipeline moves the model **whole**. Every
table's column expectations travel, including tables with nothing to do with the change being
released.

30 Oct 2026: I checked that the targets rework's stored procedures had no `fk_Practice_Site`
dependency — true, and verified — and told the owner the release "stands alone". Prod's model refresh
then failed with *"The 'fk Practice Site' column does not exist in the rowset"*, from
`_Treatment Plan Items` and three site-grained aggregates. The rename was on the critical path
regardless, and shipping it mid-release took V156, a `@Full_Reload = 1` pass over 265,299 rows, three
aggregate rebuilds and a redeploy of `Security.vw_User_Tenant_Access`.

**Why:** a proc-level check answers "will this loader run"; it cannot answer "will the model bind".
Those are different questions and only the second gates a release.

**How to apply:** before promoting the model, diff **dev vs prod column sets for every schema** —
`Config`, `Security`, `Gold`, `Input`, `Input_Stage`, not just the ones the change touched. That one
sweep found 28 gaps on this release, all of them columns added to dev by hand and never written
down. Related: [[pipeline-deploy-clears-the-models-connection]],
[[releases-touching-one-file-cannot-replay-individually]], [[a-new-model-table-has-no-rls]].

Also settled on that release: **`_Node Targets` is deliberately NOT a model table**, on either
environment. Reports read `Aggregate Period Targets`; the node fact is that aggregate's source and
the app's Targets screens, nothing more. I reported its absence as an outstanding gap twice.
