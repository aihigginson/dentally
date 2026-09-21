---
name: fabric-is-canonical-for-notebooks-and-pipelines
description: Notebooks and data pipelines live in Fabric; the repo copies are reference. Promote dev to prod with the deployment pipeline, never by writing to prod.
metadata:
  type: project
---

**Fabric is the source of truth for notebooks and data pipelines.** The files under
`Fabric/Notebooks/` — including `build_Ingest_Dentally.py` and the `.ipynb` it generates — are
reference copies, not the thing that runs. Neither workspace is git-connected, so the two can and do
drift: a commit can put a change in the repo while Fabric never sees it, and both sides look fine.

**Changes are made in the DEV workspace, then promoted with the `DEV TO PROD` deployment pipeline**
(stage 0 `DEV - DM Dentally` → stage 1 `DM Dentally`). Never write to a prod Fabric item directly —
that bypasses the promotion path and leaves prod holding something that never came through it.

Warehouse objects are the opposite way round: those are versioned in `Fabric/*.sql` and deployed by
`Scripts/Deploy.ps1` with a `Releases/Vnnn` manifest. Do not confuse the two.

**Why it matters:** asked to publish a notebook change, the obvious-looking move is to push the
repo's `.ipynb` through the Fabric API. That is the wrong method even when it produces the right
result, and applying it to prod would skip the pipeline entirely.

Useful detail if the API is ever the right tool: `getDefinition`/`updateDefinition` return
`notebook-content.py` by default and `notebook-content.ipynb` with `?format=ipynb` — two
serialisations of ONE item, not two files. Verify a write by reading it back in the other format.

See [[fabric-script-activities-dont-repoint]] for the related trap: named connections survive
promotion, so a promoted pipeline can still point at dev.
