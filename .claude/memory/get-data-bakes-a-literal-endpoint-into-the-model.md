---
name: get-data-bakes-a-literal-endpoint-into-the-model
description: "Power BI Desktop's Get Data writes a literal warehouse endpoint, so a table added that way does not repoint on promotion - check Application Users above all."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T09:10:43.568Z
---

Every table in `PBI Dentally` reaches the warehouse through the **`pServer`** parameter
(`Sql.Database(pServer, pDatabase)`), and the deployment pipeline sets that parameter per
stage — so they repoint dev→prod on promotion. A table added through **Desktop's Get Data**
instead gets a literal endpoint baked into its M, and silently keeps pointing at whichever
warehouse it was created against.

**Why:** on 2026-09-27 `Application Users` — the source of the RLS rule on all 44
tenant-bearing tables — was moved onto the V186 view `Security.vw_User_Tenant_Access` via Get
Data, so it carried `Sql.Database("…-4i26eirspjiujnltrvplquzkem.datawarehouse…")`, the **dev**
endpoint. Promoted to prod, the production model's access table pointed at the development
warehouse. Caught before any refresh: a promotion is metadata-only, so the partitions still
held prod-derived rows and the leak would have landed on the first refresh afterwards. A
pipeline data source rule would have masked it rather than fixed it, and left the literal to
be re-promoted.

**How to apply:** after any promotion, read the partition M of `Application Users` (and of
anything recently added) and confirm it says `Sql.Database(pServer, pDatabase)` — comparing
`pServer` alone is not enough, because it can be correct while a table ignores it.
`Fabric/PBI_Dentally.csx` now normalises this table's source, guarded on the literal being
present, so running the csx against the .pbix fixes it at source. Same family as
[[fabric-script-activities-dont-repoint]] and checked alongside
[[publishing-from-desktop-overwrites-a-service-refresh]].
