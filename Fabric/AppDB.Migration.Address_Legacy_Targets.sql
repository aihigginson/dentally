/* ============================================================================
   APPDB MIGRATION -- give every target an EXPLICIT node address.

   ==> RUN AFTER AppDB.Migration.Target_Level_Columns.sql AND Roles_Are_Client_Wide.sql. <==
   AppDB-dev first, then AppDB-prod.

   ==> ONE RULE, THREE SPELLINGS, AND THE ODD ONE OUT WAS THE SCREEN. <== A row written before
   Level_Type/Level_Key existed carries NULL in both, meaning "the practice named by Tenant_ID".
   Three places resolved that:

       Gold.usp_Load_Fact_Node_Targets   ISNULL(Level_Key, Tenant_ID)      correct
       Meta.usp_Sync_Input_From_AppDB    ISNULL(Level_Key, Tenant_ID)      correct
       Web/app.py  /api/target-grid      ISNULL(Level_Key, '')             WRONG

   So Maple's 106 un-addressed Practice rows keyed as ('Practice','') for the screen and
   ('Practice','100') for everything else. The Targets screen showed every box blank against
   targets the Home page was happily rendering. Dev never reproduced it: every dev row already
   carried an explicit Level_Key.

   The read is fixed in the app. This closes the other half: the SAVE path deletes by the address
   it is writing, so an un-addressed row would survive the DELETE and the INSERT would then collide
   on the computed Node_Key -- both resolve to the tenant -- and the save would fail on a duplicate
   key. Making the address explicit removes the dependence on three fallbacks agreeing.

   ==> SEMANTICALLY A NO-OP. <== Setting ('Practice', Tenant_ID) where both are NULL writes down
   exactly what NULL already meant. No figure moves, no row is added or removed, and
   Gold.Fact_Node_Targets rebuilds to the same values -- which the check at the end proves by
   counting rows per node before and after rather than taking it on trust.

   Idempotent: a second run matches nothing.
   ============================================================================ */
SET NOCOUNT ON;

IF COL_LENGTH('Input.Targets', 'Level_Type') IS NULL
    THROW 51500, 'Run AppDB.Migration.Target_Level_Columns.sql first.', 1;
GO

SELECT 'before' AS step,
       SUM(CASE WHEN Level_Type IS NULL OR Level_Key IS NULL THEN 1 ELSE 0 END) AS un_addressed,
       COUNT(*) AS rows_, SUM(Target_Value) AS sum_value
FROM   Input.Targets;
GO

/* Only rows that carry NO address at all. A row with a Level_Type and no Level_Key, or the
   reverse, is not a legacy row -- it is a bug, and it is left alone to be seen. */
UPDATE Input.Targets
SET    Level_Type = 'Practice',
       Level_Key  = CAST(Tenant_ID AS VARCHAR(64))
WHERE  Level_Type IS NULL AND Level_Key IS NULL;

PRINT 'addressed ' + CAST(@@ROWCOUNT AS VARCHAR(12)) + ' legacy row(s) to their own practice';
GO

/* ---- prove it, rather than assume it ------------------------------------ */
/* Nothing added, nothing removed, not a penny moved. */
SELECT 'after' AS step,
       SUM(CASE WHEN Level_Type IS NULL OR Level_Key IS NULL THEN 1 ELSE 0 END) AS un_addressed,
       COUNT(*) AS rows_, SUM(Target_Value) AS sum_value
FROM   Input.Targets;

/* And a half-address is a bug, not a legacy row -- it must not exist.
   Written with CASE rather than (x IS NULL) <> (y IS NULL): T-SQL has no boolean type, so
   comparing two predicates is a syntax error, not a clever test. */
SELECT 'half-addressed (must be 0)' AS check_, COUNT(*) AS rows_
FROM   Input.Targets
WHERE  CASE WHEN Level_Type IS NULL THEN 1 ELSE 0 END
     <> CASE WHEN Level_Key  IS NULL THEN 1 ELSE 0 END;

SELECT 'rows per address' AS check_, Client_ID, Level_Type, COUNT(*) AS rows_
FROM   Input.Targets GROUP BY Client_ID, Level_Type ORDER BY Client_ID, Level_Type;
GO
