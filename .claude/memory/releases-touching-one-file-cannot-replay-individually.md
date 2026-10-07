---
name: releases-touching-one-file-cannot-replay-individually
description: "Several releases changing the same .sql file only apply in order once - later environments need one combined manifest, because each release deploys the file's CURRENT state."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T15:58:37.759Z
---

A manifest deploys the **current** contents of the files it names, not a snapshot from when it
was written. So when releases N, N+1 and N+2 all change the same procedure, running N against
a fresh environment applies all three at once. Any guard in N that asserts a narrow effect
("nothing changed") then fails on the later releases' intended changes.

**Why:** on 2026-09-27 V189 (regrain capitation, no money moves), V190 (spell ends on a date,
money falls) and V191 (relabel) all edited `Gold.usp_Load_Fact_Revenue`. They passed in dev
because they were deployed as the file evolved. Deploying V189 to prod applied all three, and
its "no patient-month may change" guard fired on 241 legitimate V190 reductions. The data was
correct; the guard was scoped to a release boundary that no longer existed. Fixed with V192, a
combined manifest whose guards describe the union.

**How to apply:** when a second release touches a file an unreleased release already changed,
either fold it into the existing manifest or plan a combined one for the environments still
behind. Write guards against the **end state** of everything in flight, not against one
release's delta. Make baseline snapshots conditional (`IF OBJECT_ID(...) IS NULL`) so a
part-applied or aborted run keeps the genuine pre-change picture to verify against — that is
what saved the prod verification here. Related:
[[never-compare-two-rolling-windows-built-on-different-days]].
