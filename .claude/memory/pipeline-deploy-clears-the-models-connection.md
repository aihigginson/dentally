---
name: pipeline-deploy-clears-the-models-connection
description: "Two separate pipeline traps: a deploy wipes the model's data source binding (fix with deployment rules), and 'Different from source' is decided by model.bim, which TMDL cannot show."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-03T00:35:45.710Z
---

Two unrelated problems that looked like one, 2026-10-02/03, `PBI Analytically`:

**1. The deploy wipes the data source binding.** `gatewayId`/`datasourceId` go null and every refresh
then fails with *"uses a default data connection without explicit connection credentials"*. Fixed
with **deployment rules on the Production stage** — a **Data source rule**, plus Parameter rules for
`pServer`/`pDatabase`. Setting the values by hand (model settings → Gateway and cloud connections /
M Parameters) works until the next deploy and then silently reverts; that cost three repairs in one
evening. Verified holding through a later deploy. Connections: `Prod_WH_Dentally` 6cb8e2d4 → prod,
ServicePrincipal; `Connection to WH_Dentally` 95953c13 → dev, OAuth2. Both models should be bound
on BOTH sides.

**2. "Different from source" was the calculation group, and TMDL cannot see it.** `_Measures` was
created BY HAND in each model instead of built in dev and deployed, so they differed in two
cosmetic properties that nothing reads:

        partitions[0].name           prod "Partition"   dev "_Measures"
        calculationItems[0].ordinal  prod 0             dev absent

`Fabric/PBI_Analytically.csx` now asserts both, so the models converge on every run.

**Why:** the pipeline compares **model.bim**. `getDefinition?format=TMDL` OMITS both properties —
each side exports as nothing but `calculationGroup` + `calculationItem 'Calculation item' =
SELECTEDMEASURE()` — so a TMDL diff reports the table identical while the pipeline reports it
different, forever.

**How to apply:** when the pipeline flags an item, open its **Compare** view FIRST and read what it
names. Do not diff the TMDL and reason from that to what the UI shows — I did, four times, and
produced four wrong explanations in a row ("it's inherent", "content differs", "modified since
deployed", "a rule is missing"), each of which sent the owner off to change something. Each one came
from substituting a thing I could read for the thing I could not. When the instrument cannot see the
object, say so instead of inferring. Related: [[fabric-is-canonical-for-notebooks-and-pipelines]],
[[publishing-from-desktop-overwrites-a-service-refresh]],
[[get-data-bakes-a-literal-endpoint-into-the-model]].
