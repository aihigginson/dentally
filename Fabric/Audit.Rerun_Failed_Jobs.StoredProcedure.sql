--------------------------------------------------------------------
--  Stored Procedure :  Audit.Rerun_Failed_Jobs
--  Author           :  AIH
--  Initital Date    :  17/05/2026
--  History          :
--    *01     17/05/2026  AIH Initial Release
--  To Run           :   EXEC Audit.Rerun_Failed_Jobs
--                   :   EXEC Audit.Rerun_Failed_Jobs @Category_Code = 'BRONZE'
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Audit].[Rerun_Failed_Jobs]
GO
CREATE PROCEDURE [Audit].[Rerun_Failed_Jobs]
(
      @Category_Code   VARCHAR(100) = NULL   -- NULL reruns all categories; pass e.g. 'BRONZE', 'SILVER', 'GOLD' to filter
    , @Parent_Run_UUID VARCHAR(36)  = '00000000-0000-0000-0000-000000000000'
)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- Find all Process_Codes where the most recent execution is FAILED
        SELECT   pc.Process_Code
                , pc.Process_Name
                , pc.Process_Category_Code
                , latest.Start_Time      AS Last_Run_Time
                , latest.Error_Message   AS Last_Error
        INTO    #to_rerun
        FROM    Audit.Process_Config AS pc
        INNER JOIN (
            SELECT  Process_Name
                  , Status
                  , Start_Time
                  , Error_Message
                  , ROW_NUMBER() OVER (PARTITION BY Process_Name ORDER BY Start_Time DESC) AS rn
            FROM    Audit.Process_Execution_Log
            WHERE   Process_Name IS NOT NULL
        ) AS latest ON latest.Process_Name = pc.Process_Name
                    AND latest.rn = 1
        WHERE   latest.Status = 'FAILED'
          AND   (@Category_Code IS NULL OR pc.Process_Category_Code = @Category_Code);

        DECLARE @Code        VARCHAR(100);
        DECLARE @Name        VARCHAR(1000);
        DECLARE @Category    VARCHAR(100);
        DECLARE @Rerun_Count INT = 0;
        DECLARE @Total_Count INT;

        SELECT @Total_Count = COUNT(*) FROM #to_rerun;

        PRINT 'Rerun_Failed_Jobs: ' + CAST(@Total_Count AS VARCHAR) + ' failed job(s) to rerun'
            + CASE WHEN @Category_Code IS NOT NULL THEN ' (category: ' + @Category_Code + ')' ELSE '' END;

        WHILE EXISTS (SELECT 1 FROM #to_rerun)
        BEGIN
            SELECT TOP 1
                  @Code     = Process_Code
                , @Name     = Process_Name
                , @Category = Process_Category_Code
            FROM #to_rerun
            ORDER BY Process_Category_Code, Process_Code;

            PRINT '  Rerunning [' + @Category + '] ' + @Name + ' (' + @Code + ')';

            EXEC Audit.ETL_Run_Process
                  @Process_Code    = @Code
                , @Parent_Run_UUID = @Parent_Run_UUID;

            DELETE FROM #to_rerun WHERE Process_Code = @Code;
            SET @Rerun_Count = @Rerun_Count + 1;
        END

        DROP TABLE IF EXISTS #to_rerun;

        PRINT 'Rerun_Failed_Jobs: complete -- ' + CAST(@Rerun_Count AS VARCHAR) + ' job(s) rerun.';

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END
GO
