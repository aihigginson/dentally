---
name: client-hierarchy-attaches-to-the-site
description: "Region and Area hang off the SITE, not the tenant; Practice is derived and shows only when an area holds more than one tenant."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-28T12:13:45.280Z
---

The client tree is **Client > Region > Area > Site**, held in AppDB as `Input.Client`,
`Input.Client_Tenant`, `Input.Client_Region`, `Input.Client_Area`, `Input.Site_Area`.

**Region and Area attach to the SITE.** A client may run ONE Dentally tenant covering sites
across the country, and those sites must be placeable in different areas. Attaching the tree
to the tenant forecloses that permanently, and it is the shape a large customer is most
likely to arrive with.

**Practice is derived, never stored.** It is 1:1 with tenant and appears as a level only when
an area holds more than one tenant -- the same "does this offer a choice?" test as every
other level. A tenant whose sites span areas cannot hang under either, and the tree then
reads Client > Region > Area > Site with the practice name as a label.

**The hiding rule:** a level is shown when at least one node above it has more than one child
there. On dev, the demo client has one tenant in Manchester and a two-site tenant in London;
Region, Area and Site show, Practice does not, because London holds exactly one tenant.

**Why:** the instinct is to store Practice as a fixed level and to let the customer pick a
grain. Both are wrong -- storage grain is always the site, input grain is a UI question, and
whether a level is useful is observable rather than configured. A per-client
`Hierarchy_Grain` flag was considered and rejected: it would have had to forbid the
national-tenant case.

## Hierarchy and ACCESS are two independent stores, and that is a bug source

* **Hierarchy** (`Input.Client`, `Client_Tenant`, `Client_Region`, `Client_Area`, `Site_Area`)
  is **owned by the AppDB**. `Meta.usp_Sync_Input_From_AppDB` DELETEs the warehouse copies and
  rebuilds them from `Input_Stage` on every full sync, so **anything written warehouse-side
  disappears on the next sync**. `Region_ID`/`Area_ID` are IDENTITY in the AppDB too, so
  warehouse `MAX(ID)+1` allocation also hands out ids that database will later reissue.
  Maintain it via Settings > Hierarchy, or SQL against `AppDB-<env>.Input.*` followed by
  `python appdb_sync.py full`.
* **Access** (`Security.Client_Tenant_Access`) is **warehouse-only**. It is in no sync set and
  is **not** derived from `Input.Client_Tenant` — `usp_Sync_Access_From_AppDB` touches only
  `Security.Application_Users` and `Security.Access_Log`.

So a client can be perfectly grouped in the AppDB — tenants mapped, sites in areas, the tree
rendering correctly — and still not be able to SEE a member. That was DEV tenant 12: mapped to
client 11 in `Input.Client_Tenant`, never granted in `Security.Client_Tenant_Access`, and
nothing reported an error. Fixed 2026-10-28, alongside building Skeleton Group (client 20) over
tenants 21-24 (North/Manchester: 21,22 · North/Leeds: 23 · South/London: 24, 9 sites).

`Audit.usp_Form_Client_Group` grants access and reports `sites_with_no_area`; revision *02
removed its hierarchy writes, because a warehouse proc structurally cannot own that data.

**How to apply:** the admin screen is Settings > Hierarchy, gated by `_require_staff`
(the `@analytically.info` mailbox domain Entra asserts, not a flag in Application_Users).
Full design: the doc "Unravelling Client, Tenant, Practice, Site". Related:
[[the-acting-practice-is-part-of-the-identity]], [[embed-token-scope-stops-at-one-tenant]].
