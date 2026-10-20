---
name: sys-views-cannot-join-user-tables-in-fabric
description: "In a Fabric warehouse, sys.* cannot be correlated with a user table, and SELECT INTO #temp FROM sys.* is rejected too."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-20T15:46:24.647Z
---

A Fabric warehouse rejects any query that puts a **system view in the same plan as a user
table**:

    The query references an object that is not supported in distributed processing mode.

Both of these fail, so the usual workaround does not help:

```sql
-- fails: sys.objects correlated with a user table
SELECT COUNT(*) FROM Audit.RI_Check_Config c
WHERE NOT EXISTS (SELECT 1 FROM sys.objects o WHERE o.name = c.Fact_Table);

-- ALSO fails: materialising sys.* into a temp table first
SELECT CAST(o.name AS VARCHAR(128)) AS nm INTO #gold FROM sys.objects o ...;
```

A `sys.*`-only query is fine (`SELECT COUNT(*) FROM sys.objects WHERE name IN (...)`) --
every V2xx guard that checks whether an object exists works, because it never touches a
user table. It is the **join** that is refused.

**What to do instead:** don't write the guard. Deploy.ps1 already runs a referential-integrity
check after every manifest and it is a real control -- on 2026-10-20 V224 dropped two tables,
deployed cleanly, and the RI check failed the run with `Invalid object name
'Gold.Fact_Effective_Targets'` because Audit.RI_Check_Config still named them. That is the
check working. Cost three deploy attempts to re-learn by trying to duplicate it.

Related: [[prefer-temp-tables-over-ctes]] is the house rule for ordinary queries, but it does
not rescue this one. See also [[read-the-schema-before-querying-it]].
