---
name: scale-target-is-100-practices
description: One live practice today, target at least 100 - judge architecture by how it behaves at 100, not by today's cost.
metadata:
  type: project
---

Analytically has **one live connection today and a target of at least 100 practices**. The owner
expects to raise the Fabric capacity as customers arrive, because the subscription revenue covers
it — so **capacity cost is not the constraint; architectural scalability is**.

**Why:** stated on 2026-10-01, while deciding between two ways to cut the nightly orchestrator's
CU. I had argued against parallelising the build waves because, after shrinking the Spark pool,
the saving was about 1% of an F4 and the concurrency risk was real. That reasoning was right about
today and wrong about the product: the build runs Bronze **per tenant**, so a sequential build
that takes twenty minutes for two practices does not take twenty minutes for a hundred. The owner
also made the timing argument — work the scaling problems out now, while the volume makes mistakes
cheap.

**How to apply:** when weighing a change, ask what it does at 100 tenants, not what it saves this
month. Anything per-tenant and sequential is a wall, not an inefficiency. Cheap-and-certain
configuration wins still come first (the Spark pool was 6x for no code), but do not use "the
saving is small" to dismiss work whose real value is that it removes a ceiling. `max_parallel` in
Orchestrate_Build is the standing example: set to 1, with the author's own comment on how to fan
out a wave on a ThreadPoolExecutor with a separate pyodbc connection per worker. Related:
[[fabric-is-canonical-for-notebooks-and-pipelines]].
