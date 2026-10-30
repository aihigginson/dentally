/* ============================================================================
   APPDB MIGRATION -- a target is keyed by its NODE, not just by its tenant.

   ==> RUN THIS AGAINST AppDB-<env>. <== AppDB-dev first, prove it, then AppDB-prod.

   ==> WHY: THE PRIMARY KEY MADE THE PER-LEVEL SCREENS IMPOSSIBLE. <== PK_Input_Targets was
   (Tenant_ID, FY, Metric, Target_Level) -- from when a target could only ever be a practice's.
   The hierarchy screens enter a figure against a NODE, and several nodes share one tenant:

       Skeleton Alpha has two sites, both tenant 21.    Two site figures -> PK violation.
       Skeleton Charlie has a practice figure AND two site figures, all tenant 23. Same.

   So the second row of any multi-site practice was rejected. Not a seeding inconvenience -- the
   feature cannot store its own data without this.

   ==> THE FALLBACK IS STATED ONCE, AS THE LOADER READS IT. <== Level_Type and Level_Key are
   nullable, and seven places insert into this table without them (the original roles grid, the
   onboarding seed, the template loader, the restore script...). Making them NOT NULL would mean
   finding a node address for every one of those. Instead the key is built on two PERSISTED
   COMPUTED columns carrying exactly the ISNULL fallback Gold.usp_Load_Fact_Node_Targets applies:

       Node_Level  = ISNULL(Level_Type, 'Practice')
       Node_Key    = ISNULL(Level_Key, CAST(Tenant_ID AS VARCHAR(64)))

   An un-addressed row therefore keys as that tenant's practice -- which is what it has always
   meant -- and the uniqueness rule and the loader can no longer drift apart, because they are the
   same expression. Every existing writer is untouched.

   The computed columns do NOT reach the warehouse: Web/appdb_sync.py takes its column list from
   the TARGET (Input_Stage), so a column staging lacks is never sent.

   Idempotent: re-running backfills nothing and rebuilds nothing.
   ============================================================================ */
SET NOCOUNT ON;

/* ---- 1. the two key columns, as the loader resolves them ----------------- */
/* ==> NOT NULL HAS TO BE SAID OUT LOUD. <== Both expressions are non-nullable by inspection --
   ISNULL with a literal fallback, over a NOT NULL Tenant_ID -- but SQL Server does not infer that
   for a computed column, and a nullable column cannot be in a PRIMARY KEY. Without the explicit
   NOT NULL step 2 fails with "Cannot define PRIMARY KEY constraint on nullable column".
   A column left over from a run that predates this is dropped and re-added. */
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('Input.Targets') AND name = 'Node_Level' AND is_nullable = 1)
    ALTER TABLE Input.Targets DROP COLUMN Node_Level;
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('Input.Targets') AND name = 'Node_Key' AND is_nullable = 1)
    ALTER TABLE Input.Targets DROP COLUMN Node_Key;
GO
IF COL_LENGTH('Input.Targets', 'Node_Level') IS NULL
    ALTER TABLE Input.Targets
        ADD Node_Level AS ISNULL(Level_Type, 'Practice') PERSISTED NOT NULL;
GO
IF COL_LENGTH('Input.Targets', 'Node_Key') IS NULL
    ALTER TABLE Input.Targets
        ADD Node_Key AS ISNULL(Level_Key, CAST(Tenant_ID AS VARCHAR(64))) PERSISTED NOT NULL;
GO

/* ---- 2. the key itself --------------------------------------------------- */
/* Rebuilt unless the key already has six columns. The test counts columns rather than reading the
   name, because the key keeps its name -- and it treats NO key at all as "needs building", which
   is not hypothetical: a batch is not a transaction, so a first attempt that dropped the old key
   and then failed to add the new one leaves the table with none. */
IF NOT EXISTS (SELECT 1
               FROM   sys.indexes i
               WHERE  i.object_id = OBJECT_ID('Input.Targets')
                 AND  i.is_primary_key = 1
                 AND  (SELECT COUNT(*) FROM sys.index_columns ic
                       WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                         AND ic.key_ordinal > 0) = 6)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('Input.Targets') AND is_primary_key = 1)
        ALTER TABLE Input.Targets DROP CONSTRAINT PK_Input_Targets;

    ALTER TABLE Input.Targets
        ADD CONSTRAINT PK_Input_Targets PRIMARY KEY CLUSTERED
            (Tenant_ID, FY, Metric, Target_Level, Node_Level, Node_Key);

    PRINT 'PK_Input_Targets widened to include the node address.';
END
ELSE
    PRINT 'PK_Input_Targets already carries the node address -- nothing to do.';
GO

/* ---- 3. prove it, rather than assume it ---------------------------------- */
SELECT c.name AS key_column, ic.key_ordinal
FROM   sys.indexes i
JOIN   sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN   sys.columns c ON c.object_id = i.object_id AND c.column_id = ic.column_id
WHERE  i.object_id = OBJECT_ID('Input.Targets') AND i.is_primary_key = 1
ORDER  BY ic.key_ordinal;

/* Every row resolves to a node, and no two rows resolve to the same one. */
SELECT COUNT(*) AS rows_, COUNT(DISTINCT CONCAT(Tenant_ID, '|', FY, '|', Metric, '|',
                                                Target_Level, '|', Node_Level, '|', Node_Key))
                          AS distinct_addresses
FROM   Input.Targets;
GO
