/* ============================================================================
   APPDB MIGRATION -- the two columns that say WHICH NODE a target was entered against.

   ==> RUN THIS BEFORE AppDB.Migration.Target_Node_Key.sql. <== That script builds persisted
   computed columns over Level_Type and Level_Key; without them it fails on its second batch with an
   invalid column name, after its first batch has already run.

   ==> WHY THIS FILE EXISTS AT ALL. <== It was the gap in the set. Client_Keying adds Client_ID,
   Target_Node_Key keys on the node, Roles_Are_Client_Wide moves the rows -- but nothing anywhere
   added the two columns the last two depend on. They reached AppDB-dev by hand during development
   and were never written down, so the migration chain worked on dev and would have stopped halfway
   on prod. Found by running the chain against AppDB-prod, which still had neither.

   WHAT THEY MEAN. Together they are the ADDRESS of the node a figure was typed against:

       Level_Type   'Client' | 'Region' | 'Area' | 'Practice' | 'Site'
       Level_Key    the node's key at that level -- a Region_ID, an Area_ID, a Tenant_ID for a
                    practice, or a pk_Practice_Site for a site

   Both NULLABLE, and that is deliberate: a NULL pair means "the practice named by Tenant_ID",
   which is what every row written before the hierarchy existed means. Gold.usp_Load_Fact_Node_Targets
   reads them as ISNULL(Level_Type,'Practice') and ISNULL(Level_Key, Tenant_ID), so an old row needs
   no backfill to keep behaving exactly as it always has. Target_Node_Key then builds that same
   fallback into the key, so the rule is stated once.

   VARCHAR(10) and VARCHAR(64) match what the warehouse's Input.Targets and Input_Stage.Targets
   already declare -- the sync copies by name and type, so a wider column here would truncate there.

   Idempotent: re-running adds nothing.
   ============================================================================ */
SET NOCOUNT ON;

IF COL_LENGTH('Input.Targets', 'Level_Type') IS NULL
    ALTER TABLE Input.Targets ADD Level_Type VARCHAR(10) NULL;
GO

IF COL_LENGTH('Input.Targets', 'Level_Key') IS NULL
    ALTER TABLE Input.Targets ADD Level_Key VARCHAR(64) NULL;
GO

/* ---- prove it, rather than assume it ------------------------------------ */
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Targets'
  AND  COLUMN_NAME IN ('Client_ID', 'Level_Type', 'Level_Key')
ORDER  BY COLUMN_NAME;

/* Nothing is backfilled, so every existing row must still read as its own practice. */
SELECT 'rows that still mean their own practice' AS check_, COUNT(*) AS rows_
FROM   Input.Targets WHERE Level_Type IS NULL AND Level_Key IS NULL;
GO
