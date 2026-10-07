---
name: no-in-product-staleness-warning
description: "SETTLED: do not surface 'data as at <date>' or a skipped-refresh warning in the app. It generates support calls; monitoring plus a fast fix is the chosen answer."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-07T08:09:43.088Z
---

When the nightly build fails, `Orchestrate_Build` skips the semantic-model refresh (`REFRESH_SKIP`,
`if refresh_semantic_model and not failed`) and the app serves yesterday's data with nothing on
screen saying so. **Do not propose showing the user a staleness banner, a "data as at" stamp, or a
skipped-refresh warning.** The owner, 2026-10-07: *"In my experience that generates support calls
and we will be monitoring to fix anything ASAP in any case. Hopefully it will be rare."*

**Why:** a warning in front of a dentist converts a silent, usually same-day problem into an inbound
call the owner has to field alone. The chosen control is the existing monitor — the build's last
step POSTs `/api/monitor/health`, which emails a summary of new `Process_Execution_Log` failures —
plus fixing fast.

**How to apply:** treat a skipped refresh as an operational event, not a UI one. Flag it to the
owner, fix the cause, and leave the product silent. Do not re-raise the banner idea — see
[[dont-re-raise-settled-decisions]]. The gate itself also stays as it is: loosening it would publish
a partially built model, which is what it exists to prevent. Related:
[[preprod-is-the-plan-when-revenue-allows]], [[metrics-app-health-is-live-compute-is-a-nightly-import]].
