---
name: a-parameterised-batch-cannot-create-a-temp-table
description: "pyodbc sends parameterised SQL through sp_executesql, so a #temp created in that call dies when it returns; inline the literals in the creating batch only."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-27T14:37:42.842Z
---

**A `#temp` table created by a PARAMETERISED pyodbc `execute()` does not survive the call.**
pyodbc routes parameters through `sp_executesql`, and a temp table created inside that scope is
dropped the moment it returns. The next `execute()` fails with:

```
[42S02] Invalid object name '#seed_day'. (208)
[42S02] Statement(s) could not be prepared. (8180)
```

The error points at the READING statement, so it reads as a typo or a missing object rather than
a scope problem, and re-running the creating batch "fixes" nothing.

**Fix: the creating batch inlines its literals; everything else parameterises normally.** Reading
an outer-scope temp table from inside `sp_executesql` is fine — only CREATE is scoped. So:

```python
reasons = ','.join("'%s'" % r.replace("'", "''") for r in BLOCK_REASONS)
cur.execute(SCRATCH_SQL.format(tenant=int(tenant_id), reasons=reasons))   # no params
...
cur.execute("SELECT ... FROM #seed_day WHERE dd.Full_Date >= ?", start)   # params fine
```

Cast the int rather than trusting it, and double any quote in a string literal. These values are
ours (argparse ints, module constants), never user input — if they ever were, this stops being
safe.

Worked example: `Web/onboarding_seed.py`, `build_hours_scratch`.

Two related Fabric quirks hit in the same script:

- **`DATEDIFF(WEEK, ?, col)` cannot appear in both SELECT and GROUP BY.** Fabric will not match
  two occurrences of a parameterised expression as the same thing — "invalid in the select list
  because it is not contained in either an aggregate function or the GROUP BY clause". Compute it
  in a derived table and group outside.
- **`FORMAT()` returns `nvarchar(4000)`, which `SELECT ... INTO #temp` rejects** ("The data type
  'nvarchar(4000)' ... is not supported in this edition"). `CAST(FORMAT(...) AS VARCHAR(7))`.

Related: [[pyodbc-hides-a-throw-until-nextset]], [[prefer-temp-tables-over-ctes]].
