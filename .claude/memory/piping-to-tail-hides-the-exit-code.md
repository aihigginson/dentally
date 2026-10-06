---
name: piping-to-tail-hides-the-exit-code
description: "Never infer a long write succeeded from anything but the program's own exit status, then verify row counts - tail and timeout have each hidden a half-written Bronze."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T19:52:38.925Z
---

A long write into Bronze is only proven complete by **the program's own exit status, confirmed
by row counts afterwards**. Every wrapper around it lies in a different way.

**Twice now, on consecutive days:**

* `python seed_bronze.py ... | tail -3` reports **tail's** status. On 2026-09-26 a reseed died
  partway with `pyodbc.OperationalError 10054` (the F4 capacity dropping a connection under
  load) and the shell said `exit 0`. Bronze was left with 44,097 treatment plans against 16,280
  items, a full chain ran over it, and 361 phantom "No Items" courses looked like a logic bug in
  the change being tested.
* `timeout 1800 python seed_bronze.py ... ; echo "SEEDER_EXIT=$?"` on 2026-09-27 — written
  BECAUSE of the note above — was moved to the background by the harness, `timeout` killed the
  seeder at 301,262 of 509,648 rows with status **124**, and the completion notification still
  said "exit code 0" because the wrapping shell had succeeded. Twelve tables were empty,
  including Patient_Stats, Recalls and all of Xero.

**Why:** a partial Bronze does not look like an error. Every layer downstream loads it happily,
so the failure surfaces days later as metrics that are merely *implausible* — and plausibility
is a terrible test, because a half-written tenant can look more like a real practice than a
correct one does.

**How to apply:** never put `timeout` on a seed, and never read success from a wrapper. Run it
in the background, capture the seeder's own status, and then **count the rows before anything
downstream runs** — 35 Bronze tables for a tenant, none of them empty, totals matching the
dry run's. Treat "the seed finished" as a claim requiring evidence, not an event. When a
warehouse figure contradicts what the generator produced offline, check the load completed
before debugging the logic: counts that disagree between parent and child tables are the tell.
See [[batch-generator-changes-before-reseeding]] and
[[demo-tenant-bronze-accumulates-every-generation]].
