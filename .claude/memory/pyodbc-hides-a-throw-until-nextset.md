---
name: pyodbc-hides-a-throw-until-nextset
description: "Over ODBC a THROW after a variable-assignment SELECT surfaces on cur.nextset(), not on cur.execute() - so a failing release guard reports success from Python."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-01T20:20:01.125Z
---

A multi-statement T-SQL batch of the shape the release manifests use:

```sql
DECLARE @a INT; SELECT @a = COUNT(*) FROM ...; IF @a > 0 BEGIN THROW 50290, @e, 1; END;
```

run through `pyodbc` as `cur.execute(sql)` **returns quietly even when the THROW fires**. The
error arrives on `SQLMoreResults`, i.e. the first `cur.nextset()`. The assignment SELECT produces
no result set, so execute() has nothing to report and the exception is still queued.

**Why:** on 2026-10-01 a harness written to prove V201's guards were not vacuous printed
`passed` for all four against a fact that was definitely broken. The guards were correct all
along — three of them fired the moment the result sets were drained. Half an hour went into
suspecting the guard SQL, the grain filters and the manifest parser before the harness itself.
Same family as [[piping-to-tail-hides-the-exit-code]]: the wrapper reported success, the
operation had failed.

**How to apply:** after `cur.execute()` on anything that is not a single plain SELECT, drain it —
`while cur.nextset(): pass` — inside the same try/except, before concluding it worked.
`Deploy.ps1` is NOT affected and needs no change: `Exec1` uses ADO.NET `ExecuteNonQuery()`, which
drains the batch itself and raises `SqlException`. That was verified directly against the real
guard rather than assumed, so the guards in V197-V201 did and do guard. The trap is specific to
reading results from Python. Related: [[read-the-schema-before-querying-it]].
