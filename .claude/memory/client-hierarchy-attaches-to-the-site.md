---
name: client-hierarchy-attaches-to-the-site
description: "Region and Area hang off the SITE, not the tenant; Practice is derived and shows only when an area holds more than one tenant."
metadata:
  type: project
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

**How to apply:** the admin screen is Settings > Hierarchy, gated by `_require_staff`
(the `@analytically.info` mailbox domain Entra asserts, not a flag in Application_Users).
Full design: the doc "Unravelling Client, Tenant, Practice, Site". Related:
[[the-acting-practice-is-part-of-the-identity]], [[embed-token-scope-stops-at-one-tenant]].
