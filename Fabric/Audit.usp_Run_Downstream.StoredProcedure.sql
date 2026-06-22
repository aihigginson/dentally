--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Run_Downstream
--  Author           :  AIH
--  Initial Date     :  21/06/2026
--  History          :
--    *01     21/06/2026  AIH Initial release.
--  Purpose          :  DEV convenience: after changing one job, rebuild it and EVERYTHING
--                      downstream of it (transitive) in dependency order. Sibling of
--                      Audit.usp_Rerun_Failed_Jobs, but seeds the plan from the @Process_Code
--                      PARAMETER instead of reading FAILED rows from the execution log.
--                      Per-tenant jobs (Bronze, params hold {TID}) run for every ACTIVE tenant
--                      in Audit.Tenants (there's no failed run to recover a specific tenant
--                      from); Silver/Gold run once. Each job still goes through
--                      Audit.ETL_Run_Process, so it is fully logged in Process_Execution_Log.
--  Params           :  @Process_Code   the changed/trigger job (required)
--                      @Include_Self   1 = run the trigger job too (default); 0 = downstream only
--                      @Full_Refresh   passed to per-tenant Bronze jobs (default 0)
--  To Run           :  EXEC Audit.usp_Run_Downstream @Process_Code = 'SILVER_INVOICE_ITEMS';
--                      EXEC Audit.usp_Run_Downstream @Process_Code = 'GOLD_DIM_PATIENTS', @Include_Self = 0;
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[usp_Run_Downstream]
GO
CREATE PROCEDURE [Audit].[usp_Run_Downstream]
(
      @Process_Code    VARCHAR(100)
    , @Include_Self    BIT          = 1
    , @Full_Refresh    BIT          = 0
    , @Preview         BIT          = 0   -- 1 = return the ordered plan WITHOUT executing
    , @Parent_Run_UUID VARCHAR(36)  = '00000000-0000-0000-0000-000000000000'
)
AS
BEGIN
    SET NOCOUNT ON;

    -- All variables up front (Fabric: no re-DECLARE inside loops).
    DECLARE @Lvl     INT = 0,
            @Added   INT = 1,
            @Seq     INT = 1,
            @Max     INT = 0,
            @TnMax   INT = 0,
            @ti      INT = 1,
            @tid     INT,
            @Code    VARCHAR(100),
            @Name    VARCHAR(1000),
            @Cat     VARCHAR(100),
            @Lev     INT,
            @PerT    INT;

    BEGIN TRY

        IF NOT EXISTS (SELECT 1 FROM Audit.Process_Config WHERE Process_Code = @Process_Code)
            THROW 500040, 'usp_Run_Downstream:: @Process_Code not found in Audit.Process_Config.', 1;

        -- ── Step 1: seed the plan with the trigger job (level 0) ──────────────────
        DROP TABLE IF EXISTS #plan;
        SELECT  pc.Process_Code
              , pc.Process_Name
              , pc.Process_Category_Code
              , CAST(0 AS INT) AS Run_Level
              , CAST(CASE WHEN pc.Process_Parameters LIKE '%{TID}%' THEN 1 ELSE 0 END AS INT) AS Is_Per_Tenant
        INTO    #plan
        FROM    Audit.Process_Config pc
        WHERE   pc.Process_Code = @Process_Code;

        -- ── Step 2: iteratively add transitive downstream dependencies ───────────
        WHILE @Added > 0
        BEGIN
            SET @Lvl = @Lvl + 1;
            INSERT INTO #plan (Process_Code, Process_Name, Process_Category_Code, Run_Level, Is_Per_Tenant)
            SELECT  pc.Process_Code
                  , pc.Process_Name
                  , pc.Process_Category_Code
                  , @Lvl
                  , CASE WHEN pc.Process_Parameters LIKE '%{TID}%' THEN 1 ELSE 0 END
            FROM    Audit.Process_Dependency pd
            JOIN    Audit.Process_Config     pc ON pc.Process_Code = pd.Next_Process_Code
            WHERE   pd.Is_Active = 1
              AND   pd.Prev_Process_Code IN (SELECT Process_Code FROM #plan WHERE Run_Level = @Lvl - 1)
              AND   pd.Next_Process_Code NOT IN (SELECT Process_Code FROM #plan);
            SET @Added = @@ROWCOUNT;
        END

        -- ── Step 3: order the plan (skip level 0 if @Include_Self = 0) ───────────
        DROP TABLE IF EXISTS #ordered;
        SELECT  ROW_NUMBER() OVER (ORDER BY Run_Level, Process_Category_Code, Process_Code) AS Seq
              , Process_Code, Process_Name, Process_Category_Code, Run_Level, Is_Per_Tenant
        INTO    #ordered
        FROM    #plan
        WHERE   (@Include_Self = 1 OR Run_Level > 0);

        -- Active tenants (numbered) for per-tenant jobs.
        DROP TABLE IF EXISTS #tn;
        SELECT ROW_NUMBER() OVER (ORDER BY Tenant_ID) AS rn, Tenant_ID
        INTO   #tn FROM Audit.Tenants WHERE Is_Active = 1;
        SET @TnMax = (SELECT ISNULL(MAX(rn), 0) FROM #tn);
        SET @Max   = (SELECT ISNULL(MAX(Seq), 0) FROM #ordered);

        PRINT 'usp_Run_Downstream from ' + @Process_Code
            + ' (include_self=' + CAST(@Include_Self AS VARCHAR) + '): ' + CAST(@Max AS VARCHAR) + ' job(s).';

        -- ── Preview: return the plan, run nothing ────────────────────────────────
        IF @Preview = 1
        BEGIN
            SELECT Seq, Run_Level, Process_Category_Code, Process_Code, Process_Name, Is_Per_Tenant
            FROM   #ordered ORDER BY Seq;
            DROP TABLE IF EXISTS #plan;
            DROP TABLE IF EXISTS #ordered;
            DROP TABLE IF EXISTS #tn;
            RETURN;
        END

        -- ── Step 4: execute in dependency order ──────────────────────────────────
        WHILE @Seq <= @Max
        BEGIN
            SELECT  @Code = Process_Code, @Name = Process_Name, @Cat = Process_Category_Code,
                    @Lev = Run_Level, @PerT = Is_Per_Tenant
            FROM    #ordered WHERE Seq = @Seq;

            IF @PerT = 1
            BEGIN
                SET @ti = 1;
                WHILE @ti <= @TnMax
                BEGIN
                    SELECT @tid = Tenant_ID FROM #tn WHERE rn = @ti;
                    PRINT '  [L' + CAST(@Lev AS VARCHAR) + '] [' + @Cat + '] ' + @Name + '  (tenant ' + CAST(@tid AS VARCHAR) + ')';
                    EXEC Audit.ETL_Run_Process @Process_Code = @Code, @Parent_Run_UUID = @Parent_Run_UUID,
                                               @Tenant_ID = @tid, @Full_Refresh = @Full_Refresh;
                    SET @ti = @ti + 1;
                END
            END
            ELSE
            BEGIN
                PRINT '  [L' + CAST(@Lev AS VARCHAR) + '] [' + @Cat + '] ' + @Name;
                EXEC Audit.ETL_Run_Process @Process_Code = @Code, @Parent_Run_UUID = @Parent_Run_UUID;
            END

            SET @Seq = @Seq + 1;
        END

        PRINT 'usp_Run_Downstream: complete.';

        DROP TABLE IF EXISTS #plan;
        DROP TABLE IF EXISTS #ordered;
        DROP TABLE IF EXISTS #tn;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END
GO
