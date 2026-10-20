---
name: nightly-model-refresh-reports-false-success
description: The 22:00 model refresh completes in ~9s and reports success without publishing; ~30-45s is a real one.
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-20T11:59:07.164Z
---

PROD `PBI Dentally` refreshes nightly, reports **Completed**, lists all **57 tables** as
processed — and can publish nothing. Found 2026-10-20, after Maple appeared stale since
12 Oct while the warehouse was perfectly current.

**The tell is DURATION.** A real refresh of that model takes **30-45 seconds**. The
nightly ones were taking **9-15 seconds**. PROD holds more data than DEV, so a PROD
refresh finishing in a quarter of DEV's time is the alarm.

Cause is `Fabric/Notebooks/Orchestrate_Build.ipynb` cell 11, which already warns about
itself in its own comments:

* `fabric.refresh_dataset(...)` is **fire and forget** — it requests a refresh and
  returns, and the notebook logs `REFRESH_DONE` whatever happens afterwards.
* It waits a FIXED `refresh_settle_seconds` for the SQL endpoint to catch up with the
  warehouse commit. When the endpoint has not caught up, the refresh reads the old
  snapshot, finds nothing changed, finishes in seconds and honestly reports success.

**Symptom to recognise:** facts look fine but everything "relative to today" is days
behind, because `List Date` / `List Date Unconstrained` keep an old `Relative Day`
anchor. The Day Book's forward grid filters `Relative Day > 0`, so a stale anchor makes
it open on a date a week in the past — which reads as "the data stopped refreshing".

**Immediate unblock:** refresh the model by hand. That fixed it on 2026-10-20.

**Stopgap in place since 2026-10-20:** the owner added a **07:00 scheduled refresh** as a
catch-all, so a 22:00 refresh that published nothing gets a second chance hours later when
the endpoint has caught up. It hides the symptom, not the fault, and the duration tell
still works on it: a 07:00 run finishing in ~9s published nothing either. Proper fix
deferred behind more urgent work — do not re-raise it unprompted.

**Do not diagnose this from refresh status.** Status, `refreshType`, and the processed
object list were all green and all useless here. Check, in order: the warehouse view
(`SELECT MAX(Full_Date) FROM PBI.[List Date] WHERE [Relative Day] = 0`), then refresh
DURATION in the history, then the deployed report definition. Same family as
[[piping-to-tail-hides-the-exit-code]] and [[a-silent-except-froze-patient-stats]].

Fix not yet applied: poll `list_refresh_requests` until the request completes, gate on
the endpoint having caught up rather than on a sleep, and assert after refresh that the
model's anchor equals today. Remember [[fabric-is-canonical-for-notebooks-and-pipelines]] —
the edit belongs in Fabric, not the repo copy.
