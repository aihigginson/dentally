---
name: the-build-dag-is-not-a-fabric-item
description: Promoting every notebook and pipeline leaves the build DAG untouched — it lives in warehouse tables the deployment pipeline does not carry.
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-30T21:43:04.465Z
---

`Orchestrate_Build` names **no stored procedure at all**. It reads `Audit.Process_Config` and
`Audit.Process_Dependency` — **tables in `WH_Dentally`**. The Fabric deployment pipeline promotes
*items* (notebooks, pipelines, reports, models, the lakehouse, the warehouse object), not table
**rows**.

So "Fabric is up to date" says nothing about which procedures the nightly will actually run.

30 Oct 2026, after the owner promoted every item for the targets release, prod's DAG still had:

    GOLD_AGG_DAILY_TARGETS -> the loader the release RETIRED   wired in, 2 live edges
    GOLD_FACT_NODE_TARGETS                                     absent
    GOLD_AGG_PERIOD_TARGETS                                    absent

The build would have run a procedure that was about to be dropped and never built the new chain, so
`Fact_Node_Targets` and `Aggregate_Period_Targets` would have gone stale from the moment the release
finished — **silently**, because the reports keep rendering the last hand-run figures. Fixed by
V157, which copies dev's wiring rather than inventing it.

**Why:** the DAG is data, and every instinct about "deploying" treats it as code.

**How to apply:** after any release that adds or retires a loader, diff
`Audit.Process_Config` and `Audit.Process_Dependency` between the two warehouses before believing
the nightly will do the right thing — and before dropping the old loader, because unwiring has to
come first. `Audit.Process_Execution_Log` shows what the build *actually* ran last night, which is
the cheapest way to catch this. Related: [[fabric-is-canonical-for-notebooks-and-pipelines]],
[[fabric-script-activities-dont-repoint]], [[the-model-is-one-artifact]],
[[changing-a-fact-means-sweeping-its-derivations]].
