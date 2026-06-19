--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Rerun_Failed_Jobs
--  Author           :  AIH
--  Initital Date    :  17/05/2026
--  History          :
--    *01     17/05/2026  AIH Initial Release
--    *02     17/05/2026  AIH Add transitive downstream dependency reruns via Process_Dependency
--    *03     17/05/2026  AIH Replace temp table execution loop with Audit.Rerun_Plan permanent table
--    *04     17/05/2026  AIH Fix: match on Process_Options = Process_Parameters (not Process_Name only)
--                            Fix: temp table for expansion only; single clean INSERT to Rerun_Plan
--    *05     19/06/2026  AIH Bronze is now one templated config row per table (params hold {TID}/{FR}),
--                            so Process_Options no longer equals Process_Parameters. Seed by
--                            Process_Name (1:1 with Process_Code) + capture the failed run's resolved
--                            Process_Options; re-execute with the parsed @Tenant_ID/@Full_Refresh so the
--                            correct tenant is rerun. ROW_NUMBER still partitions by (Name,Options) so
--                            each failed tenant seeds its own row.
--  To Run           :   EXEC Audit.usp_Rerun_Failed_Jobs
--                   :   EXEC Audit.usp_Rerun_Failed_Jobs @Category_Code = 'BRONZE'
--  To inspect plan  :   SELECT * FROM Audit.Rerun_Plan ORDER BY Rerun_ID DESC, Exec_Seq
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Audit].[usp_Rerun_Failed_Jobs]
GO
CREATE PROCEDURE [Audit].[usp_Rerun_Failed_Jobs]
(
      @Category_Code   VARCHAR(100) = NULL   -- NULL reruns all categories; pass e.g. 'BRONZE', 'SILVER', 'GOLD' to filter
    , @Parent_Run_UUID VARCHAR(36)  = '00000000-0000-0000-0000-000000000000'
)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        DECLARE @Rerun_ID UNIQUEIDENTIFIER;
        SET @Rerun_ID = NEWID();

        -- ── Step 1: seed temp table with directly-failed jobs ─────────────────
        -- Process_Name is now 1:1 with Process_Code (Bronze collapsed to one job per
        -- table), so join on Process_Name only. ROW_NUMBER partitions by
        -- (Process_Name, Process_Options) so each failed TENANT of a Bronze job seeds
        -- its own row; the resolved Process_Options is captured as Failed_Options and
        -- carries the @Tenant_ID used to re-execute it (Step 4).
        SELECT   pc.Process_Code
                , pc.Process_Name
                , pc.Process_Category_Code
                , CAST(0 AS INT) AS Run_Level
                , CAST(0 AS INT) AS Is_Downstream
                , latest.Process_Options AS Failed_Options
        INTO    #plan
        FROM    Audit.Process_Config AS pc
        INNER JOIN (
            SELECT  Process_Name
                  , Process_Options
                  , Status
                  , ROW_NUMBER() OVER (PARTITION BY Process_Name, Process_Options ORDER BY Start_Time DESC) AS rn
            FROM    Audit.Process_Execution_Log
            WHERE   Process_Name   IS NOT NULL
              AND   Process_Options IS NOT NULL
        ) AS latest ON latest.Process_Name = pc.Process_Name
                    AND latest.rn = 1
        WHERE   latest.Status = 'FAILED'
          AND   (@Category_Code IS NULL OR pc.Process_Category_Code = @Category_Code);

        -- ── Step 2: iteratively add transitive downstream dependencies ─────────
        DECLARE @Current_Level INT = 0;
        DECLARE @Added         INT = 1;

        WHILE @Added > 0
        BEGIN
            SET @Current_Level = @Current_Level + 1;

            -- Downstream jobs (Silver/Gold) are tenant-agnostic -> no Failed_Options.
            INSERT INTO #plan (Process_Code, Process_Name, Process_Category_Code, Run_Level, Is_Downstream, Failed_Options)
            SELECT   pc.Process_Code
                   , pc.Process_Name
                   , pc.Process_Category_Code
                   , @Current_Level
                   , 1
                   , NULL
            FROM    Audit.Process_Dependency AS pd
            INNER JOIN Audit.Process_Config  AS pc ON pc.Process_Code = pd.Next_Process_Code
            WHERE   pd.Is_Active = 1
              AND   pd.Prev_Process_Code IN (SELECT Process_Code FROM #plan WHERE Run_Level = @Current_Level - 1)
              AND   pd.Next_Process_Code NOT IN (SELECT Process_Code FROM #plan);

            SET @Added = @@ROWCOUNT;
        END

        -- ── Step 3: write the final ordered plan to Audit.Rerun_Plan once ─────
        -- Exec_Seq is assigned here via ROW_NUMBER — this is the only INSERT,
        -- so there are no duplicate sequence numbers.
        INSERT INTO Audit.Rerun_Plan (Rerun_ID, Exec_Seq, Process_Code, Process_Name, Process_Category_Code, Run_Level, Is_Downstream, Failed_Options, Planned_At)
        SELECT   @Rerun_ID
               , ROW_NUMBER() OVER (ORDER BY Run_Level, Process_Category_Code, Process_Code, Failed_Options)
               , Process_Code
               , Process_Name
               , Process_Category_Code
               , Run_Level
               , Is_Downstream
               , Failed_Options
               , SYSUTCDATETIME()
        FROM    #plan;

        DROP TABLE IF EXISTS #plan;

        -- ── Step 4: execute in sequence ───────────────────────────────────────
        DECLARE @Code        VARCHAR(100);
        DECLARE @Name        VARCHAR(1000);
        DECLARE @Category    VARCHAR(100);
        DECLARE @Level       INT;
        DECLARE @IsDown      INT;
        DECLARE @Rerun_Count INT = 0;
        DECLARE @Down_Count  INT = 0;
        DECLARE @Seq         INT = 1;
        DECLARE @Max_Seq     INT;
        DECLARE @FailedOpts  VARCHAR(4000);
        DECLARE @T_ID        INT;
        DECLARE @FR          BIT;
        DECLARE @eq          INT;
        DECLARE @cm          INT;
        DECLARE @eq2         INT;

        SELECT @Max_Seq = COUNT(*) FROM Audit.Rerun_Plan WHERE Rerun_ID = @Rerun_ID;

        PRINT 'usp_Rerun_Failed_Jobs: ' + CAST(@Max_Seq AS VARCHAR) + ' job(s) to run'
            + CASE WHEN @Category_Code IS NOT NULL THEN ' (category filter: ' + @Category_Code + ')' ELSE '' END;
        PRINT 'Rerun_ID: ' + CAST(@Rerun_ID AS VARCHAR(36));
        PRINT 'Inspect: SELECT * FROM Audit.Rerun_Plan WHERE Rerun_ID = ''' + CAST(@Rerun_ID AS VARCHAR(36)) + ''' ORDER BY Exec_Seq';

        WHILE @Seq <= @Max_Seq
        BEGIN
            SET @Code = NULL;

            SELECT  @Code       = Process_Code
                  , @Name       = Process_Name
                  , @Category   = Process_Category_Code
                  , @Level      = Run_Level
                  , @IsDown     = Is_Downstream
                  , @FailedOpts = Failed_Options
            FROM    Audit.Rerun_Plan
            WHERE   Rerun_ID = @Rerun_ID
              AND   Exec_Seq = @Seq;

            IF @Code IS NOT NULL
            BEGIN
                IF @IsDown = 0
                    PRINT '  [level ' + CAST(@Level AS VARCHAR) + '] rerunning (failed)      [' + @Category + '] ' + @Name;
                ELSE
                    PRINT '  [level ' + CAST(@Level AS VARCHAR) + '] rerunning (downstream)  [' + @Category + '] ' + @Name;

                -- Recover the tenant (and full-refresh) from the failed run's resolved
                -- options so the right tenant is rerun. NULL for tenant-agnostic
                -- Silver/Gold jobs (a no-op in ETL_Run_Process).
                SET @T_ID = NULL;
                SET @FR   = NULL;
                IF @FailedOpts IS NOT NULL AND CHARINDEX('@Tenant_ID', @FailedOpts) > 0
                BEGIN
                    SET @eq = CHARINDEX('=', @FailedOpts, CHARINDEX('@Tenant_ID', @FailedOpts));
                    SET @cm = CHARINDEX(',', @FailedOpts, @eq);
                    IF @cm = 0 SET @cm = LEN(@FailedOpts) + 1;
                    SET @T_ID = TRY_CAST(TRIM(SUBSTRING(@FailedOpts, @eq + 1, @cm - @eq - 1)) AS INT);

                    IF CHARINDEX('@Full_Refresh', @FailedOpts) > 0
                    BEGIN
                        SET @eq2 = CHARINDEX('=', @FailedOpts, CHARINDEX('@Full_Refresh', @FailedOpts));
                        SET @FR  = TRY_CAST(TRIM(SUBSTRING(@FailedOpts, @eq2 + 1, LEN(@FailedOpts) - @eq2)) AS BIT);
                    END
                END

                EXEC Audit.ETL_Run_Process
                      @Process_Code    = @Code
                    , @Parent_Run_UUID = @Parent_Run_UUID
                    , @Tenant_ID       = @T_ID
                    , @Full_Refresh    = @FR;

                IF @IsDown = 0
                    SET @Rerun_Count = @Rerun_Count + 1;
                ELSE
                    SET @Down_Count = @Down_Count + 1;
            END

            SET @Seq = @Seq + 1;
        END

        PRINT 'usp_Rerun_Failed_Jobs: complete -- '
            + CAST(@Rerun_Count AS VARCHAR) + ' failed job(s) rerun, '
            + CAST(@Down_Count  AS VARCHAR) + ' downstream job(s) rerun.';

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END
GO
