---
name: fabric-writes-from-the-app-need-autocommit
description: "_fabric_conn() defaults to a transaction, so a warehouse write that closes without committing silently rolls back while reporting success - and the gitignored Scripts/_qp.py helper had the same gap."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-02T12:13:39.005Z
---

`Web/app.py`'s `_fabric_conn(autocommit=False)` defaults to a **transaction**. Every handler in the
app closes its connection without calling `commit()`, so a write opened with a bare `_fabric_conn()`
is discarded on close.

The reason this is dangerous rather than merely wrong: the endpoint reads the figures back **inside
its own uncommitted transaction**, so the response reports the new totals and looks entirely
correct. Only a *second* request shows the month unchanged. Nothing in the response distinguishes it
from a working write.

Any handler that writes to the warehouse must use `_fabric_conn(autocommit=True)` — which is what
every pre-existing warehouse writer does. `billing_run.py`'s own `_connect()` does the same.

Caught by driving the real endpoints against dev (see
[[local-app-tests-cant-read-key-vault]]); a unit test with a fake cursor cannot see it, so
`test_admin_writes_commit` asserts the flag directly instead.

## The same gap in the local query helpers (2026-10-02)

`Scripts/_q.py` (dev) and `Scripts/_qp.py` (prod) are **gitignored** (`.gitignore: Scripts/_*`), so
they are per-machine and drift silently. `_q.py` had `autocommit=True`; **`_qp.py` did not.**

An `EXEC` of `Gold.usp_Load_Fact_Daily_Targets` + `Gold.usp_Load_Aggregate_Period_Targets` through
`_qp.py` therefore rolled back on close, printed nothing, and read as success — the
net_patient_growth variance band stayed at 10 and I briefly blamed the targets chain for needing an
upstream proc. The same two procs on an autocommit connection moved it to 1.00 immediately.

**==> THE ASYMMETRY WAS THE TRAP. <==** The DEV helper was safe and the PROD one was not, so the
environment where a silent rollback matters most was the one missing the guard — and dev working
first is precisely what makes you trust prod. Fixed locally, but the file is gitignored, so **on a
new machine check both helpers before using either to write.** Better still, use a purpose-written
script with `autocommit=True` AND a read-back assertion for any write: never conclude a write
worked because nothing was printed. Related: [[piping-to-tail-hides-the-exit-code]],
[[pyodbc-hides-a-throw-until-nextset]].
