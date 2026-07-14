--DECLARE @i BIGINT=0,@u BIGINT=0,@d BIGINT=0; EXEC [Audit].[usp_Check_Referential_Integrity] @Mode='PROD',@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Check_Referential_Integrity
--  Author           :  AIH
--  Initial Date     :  09/07/2026
--  Purpose          :  Post-build integrity gate. PBI import models silently fan out / drop
--                      rows when a fact fk does not resolve to a dim pk (a "dangling" key --
--                      e.g. after a dim was DROP/CREATE-recreated and its ROW_NUMBER pk shifted
--                      while the watermark-incremental fact kept the old fk). Checks:
--                        1. every dim referenced in Audit.RI_Check_Config has its pk = -1 sentinel
--                        2. every fact fk (except -1) resolves to its target pk (RI)
--                        3. (WARN) any fk that is >= @Warn_Sentinel_Pct % on -1 (resolution likely broken)
--                      Driven by Audit.RI_Check_Config; results persisted to Audit.RI_Check_Result
--                      (NEITHER sys.* NOR #temp inside dynamic SQL -- Fabric's distributed engine
--                      rejects both). On any HARD violation it THROWS, so run via ETL_Run_Process
--                      it logs FAILED to the Execution log; a clean run logs SUCCESS. Wire it as
--                      the LAST DAG job so a broken build cannot ship to PBI.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Audit].[usp_Check_Referential_Integrity]
GO
CREATE PROCEDURE [Audit].[usp_Check_Referential_Integrity]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Warn_Sentinel_Pct INT          = 90    -- fk with >= this % of rows on -1 -> WARN (broken resolution)
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    BEGIN TRY
        DECLARE @Now datetime2(3) = SYSUTCDATETIME();
        DELETE FROM Audit.RI_Check_Result;

        DECLARE @sql NVARCHAR(MAX);
        DECLARE @dt VARCHAR(30) = CONVERT(VARCHAR(30), @Now, 121);

        -- ---- 1. SENTINEL: every referenced dim must have a pk = -1 row --------------
        SELECT @sql = STRING_AGG(CAST(
            'INSERT INTO Audit.RI_Check_Result SELECT ''' + @dt + ''',''SENTINEL'',''' + Dim_Table + ''',''' + PK_Column
          + ' = -1 missing'', 1 WHERE NOT EXISTS (SELECT 1 FROM Gold.' + QUOTENAME(Dim_Table) + ' WHERE ' + QUOTENAME(PK_Column) + ' = -1);' AS VARCHAR(MAX)), CHAR(10))
        -- Dim_Date is excluded: its unknowns are NULL, not -1 (no sentinel row by design).
        FROM (SELECT DISTINCT Dim_Table, PK_Column FROM Audit.RI_Check_Config WHERE Is_Active = 1 AND Dim_Table <> 'Dim_Date') d;
        IF @sql IS NOT NULL EXEC sp_executesql @sql;

        -- ---- 2. ORPHAN count per relationship (fk<>-1) + WARN (mostly -1) -----------
        SELECT @sql = STRING_AGG(CAST(
            'INSERT INTO Audit.RI_Check_Result SELECT ''' + @dt + ''',''ORPHAN'',''' + Fact_Table + ''',''' + FK_Column + ' -> ' + Dim_Table + '.' + PK_Column
          + ''', COUNT_BIG(*) FROM Gold.' + QUOTENAME(Fact_Table) + ' f WHERE f.' + QUOTENAME(FK_Column) + ' IS NOT NULL AND f.'
          + QUOTENAME(FK_Column) + ' <> -1 AND NOT EXISTS (SELECT 1 FROM Gold.' + QUOTENAME(Dim_Table) + ' d WHERE d.'
          + QUOTENAME(PK_Column) + ' = f.' + QUOTENAME(FK_Column) + ');' + CHAR(10)
          + 'INSERT INTO Audit.RI_Check_Result SELECT ''' + @dt + ''',''WARN_M1'',''' + Fact_Table + ''',''' + FK_Column + ' >= '
          + CAST(@Warn_Sentinel_Pct AS VARCHAR) + '% on -1 (resolution?)'', s FROM (SELECT CASE WHEN COUNT_BIG(*)=0 THEN 0 ELSE '
          + 'CAST(100.0*SUM(CASE WHEN f.' + QUOTENAME(FK_Column) + '=-1 THEN 1 ELSE 0 END)/COUNT_BIG(*) AS BIGINT) END s FROM Gold.'
          + QUOTENAME(Fact_Table) + ' f) q WHERE s >= ' + CAST(@Warn_Sentinel_Pct AS VARCHAR) + ';' AS VARCHAR(MAX)), CHAR(10))
        FROM Audit.RI_Check_Config WHERE Is_Active = 1;
        IF @sql IS NOT NULL EXEC sp_executesql @sql;

        -- ---- report + gate --------------------------------------------------------
        DECLARE @sentinel_bad INT    = (SELECT COUNT(*)             FROM Audit.RI_Check_Result WHERE Kind = 'SENTINEL');
        DECLARE @orphan_rel   INT    = (SELECT COUNT(*)             FROM Audit.RI_Check_Result WHERE Kind = 'ORPHAN' AND Bad_Count > 0);
        DECLARE @orphan_rows  BIGINT = (SELECT ISNULL(SUM(Bad_Count),0) FROM Audit.RI_Check_Result WHERE Kind = 'ORPHAN');
        DECLARE @warn         INT    = (SELECT COUNT(*)             FROM Audit.RI_Check_Result WHERE Kind = 'WARN_M1');

        PRINT '--- Referential Integrity check ---';
        SELECT Kind, Obj, Detail, Bad_Count FROM Audit.RI_Check_Result
        WHERE Kind <> 'ORPHAN' OR Bad_Count > 0
        ORDER BY CASE Kind WHEN 'SENTINEL' THEN 1 WHEN 'ORPHAN' THEN 2 ELSE 3 END, Bad_Count DESC;

        IF (@sentinel_bad + @orphan_rel) > 0
        BEGIN
            DECLARE @msg VARCHAR(500) =
                'RI CHECK FAILED: ' + CAST(@sentinel_bad AS VARCHAR) + ' dim(s) missing -1 sentinel; '
              + CAST(@orphan_rel AS VARCHAR) + ' fk->dim relationship(s) with orphans ('
              + CAST(@orphan_rows AS VARCHAR) + ' rows); ' + CAST(@warn AS VARCHAR) + ' warning(s). See Audit.RI_Check_Result.';
            THROW 51000, @msg, 1;
        END
        PRINT 'RI CHECK PASSED: every dim has a -1 sentinel; every fact fk resolves to a dim pk. Warnings: ' + CAST(@warn AS VARCHAR) + '.';
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
