---
name: fabric-rest-cannot-pass-an-array-notebook-parameter
description: Fabric's RunNotebook REST job rejects list-typed parameters like only_entities — scalars are fine; use the UI or notebook-to-notebook for lists.
metadata:
  type: reference
---

`Ingest_Dentally` takes `only_entities` (a Python list, e.g. `["recalls"]`) in its parameters
cell — **cell 1**, eleventh assignment down, just under `run_uuid`. It is present and
identical in the repo, the live DEV notebook and the live PROD notebook.

**But it cannot be passed through the Fabric REST job API.**
`POST /v1/workspaces/{ws}/items/{id}/jobs/instances?jobType=RunNotebook` fails at run time with

    Unable to convert only_entities to array.

Tried and rejected, all three: `"value": ["recalls"]`, `"value": "[\"recalls\"]"`,
`"value": "recalls"` — each with `"type": "array"`. Every SCALAR parameter
(`only_tenant`, `dentally_env`, `full_refresh`, `updated_after`, `sample_pages`) goes
through fine. The POST returns 202 either way; the failure appears in the job instance.

**Why:** the channel, not the notebook. `Orchestrate_Onboarding` passes the same parameter
happily because it uses `mssparkutils.notebook.run(...)` notebook-to-notebook, where a real
Python list survives.

**How to apply:** for an entity-scoped pull, run it from the Fabric UI (the owner does this in
seconds), or from a throwaway notebook that calls `notebook.run` with the list. Do NOT fall
back to omitting `only_entities` with `full_refresh=True` — that forces the cold path for
EVERY entity, which is the full onboarding workload for the practice on the F4 that also
serves the live site.

**The recalls backfill recipe**, which worked on both environments on 2026-10-26:
`only_tenant="100"`, `dentally_env="dev"|"prod"`, `full_refresh=True`,
`only_entities=["recalls"]`. About 230 pages (the API returns every historical cycle, ~23k
recalls, not the ~9.3k Bronze keeps after its current-cycle dedupe — sizing it off Bronze
underestimates by 2.5x). Then reload BRONZE -> SILVER.Recalls -> Silver.Recall_Reminders ->
Gold.Fact_Recalls -> the aggregate; skipping `Silver.usp_Load_Recalls` builds Gold from a
stale Silver and rows contradict themselves. Related:
[[fabric-is-canonical-for-notebooks-and-pipelines]], [[bronze-recalls-cannot-be-dropped]],
[[never-run-exploratory-dax-on-the-shared-capacity]].
