---
name: nightly-model-refresh-reports-false-success
description: "SOLVED 2026-10-28: sempy's refresh_dataset defaults to type=Automatic, which refreshes nothing in ~6s and reports success. Pass refresh_type='full'."
metadata:
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-28T08:01:14.398Z
---

**CAUSE FOUND 2026-10-28: `fabric.refresh_dataset()` defaults to `refresh_type="automatic"`.**
In the Enhanced Refresh API, `Automatic` means "refresh only what the incremental policy says
needs it". With nothing it considers stale it reports **all 57 objects Completed in ~6 seconds**
and the data does not move — and Fabric records that as a successful refresh, because on its own
terms it is.

Proven from the PROD refresh history for a single day, same model, same API:

```
2026-10-27 22:27  ViaEnhancedApi  type=Automatic   6s   model stayed on 2026-10-26
2026-10-27 08:05  ViaEnhancedApi  type=Full       22s   landed
2026-10-27 07:38  ViaEnhancedApi  type=Full       30s   landed
```

**Fix:** `fabric.refresh_dataset(dataset=..., workspace=..., refresh_type="full")` in
`Orchestrate_Build` cell 13. Applied to DEV and promoted 2026-10-28. ==> UNPROVEN IN PROD AS OF
WRITING. <== It had not yet run a night.

**The duration tell still works and is still the fastest check.** A real refresh of PROD
`PBI Dentally` takes 30-45s; 6-15s published nothing. Get it from the refresh history, and for a
`ViaEnhancedApi` row `GET /refreshes/{requestId}` returns the `type` — which is what settled this
after status, `refreshType` and the 57-object list were all green and all useless.

**Symptom to recognise:** facts look fine but everything "relative to today" is days behind,
because `List Date` keeps an old `Relative Day` anchor. The Day Book's forward grid filters
`Relative Day > 0`, so a stale anchor opens it on a date in the past.

**Immediate unblock:** refresh by hand. The history shows OnDemand refreshes propping PROD up on
25, 26, 27 and 28 Oct, which is why the model read current while `REFRESH_DONE` had not been
logged since 19 Oct.

**STILL OPEN — the settle loop dies silently.** Separate fault. On 20-26 Oct the build logged
`REFRESH_SETTLE` and then NOTHING: no `REFRESH_START`, no `REFRESH_ENDPOINT_STALE`, no
`COMPLETE`, no `MONITOR`. A timeout would log the stale path, so `_endpoint_anchor()` is throwing
inside the wait loop and taking the rest of the cell with it. Seven nights, intermittent — the
27th got through. ==> DEFERRED BY THE OWNER 2026-10-28 to see whether `full` alone stabilises it;
do not re-raise unprompted. <== The fix is to guard `_endpoint_anchor()` so a throw logs and falls
through, same shape as the `refresh_error` try/except already around the monitor poke.

The model-anchor assertion added earlier (`REFRESH_STALE` / `REFRESH_FAILED` when the model's
`Relative Day = 0` date does not equal the warehouse's) is what caught all of this. Keep it.

Same family as [[piping-to-tail-hides-the-exit-code]] and [[a-silent-except-froze-patient-stats]]:
a wrapper reporting success for work that did not happen. Edits belong in Fabric, not the repo
copy — [[fabric-is-canonical-for-notebooks-and-pipelines]].
