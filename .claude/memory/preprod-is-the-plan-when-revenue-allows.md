---
name: preprod-is-the-plan-when-revenue-allows
description: A PREPROD environment is the intended topology once there is income; an overnight PREPROD build must pass before anything reaches PROD. Capacity cost is the only blocker.
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-07T08:09:54.620Z
---

The intended end state, stated by the owner on 2026-10-07: **dev → PREPROD → PROD**, where a change
must survive an **overnight PREPROD build** before it is promoted, and only emergency fixes go
straight to PROD. *"Money (and therefore capacity) is the current limiting factor."*

So the two-environment setup today is a budget constraint, not a design preference. Until then,
hand-deployed releases into PROD are the norm and are expected to carry their own guards.

**How to apply:** do not propose PREPROD as if it were a new idea, and do not treat the current
dev→prod flow as an oversight to fix. When weighing how much verification a release should carry,
assume there is NO overnight gate before prod — which is exactly how V211 shipped a split whose
consumers only run at night and broke prod's build the same evening (see
[[changing-a-fact-means-sweeping-its-derivations]]). A release must therefore run its consumers
itself. That cost falls away once PREPROD exists, which is part of why the owner wants it.

Related: [[scale-target-is-100-practices]], [[a-report-render-costs-about-27-cu-seconds]],
[[no-in-product-staleness-warning]].
