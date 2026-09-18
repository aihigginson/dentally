---
name: fabric-writes-from-the-app-need-autocommit
description: "_fabric_conn() defaults to a transaction, so a warehouse write that closes without committing silently rolls back while reporting success."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-18T10:13:35.375Z
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
