--------------------------------------------------------------------
--  Stored Procedure :  Audit.ETL_Execution_Log_Cleanup
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Audit.ETL_Execution_Log_Cleanup @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Audit].[ETL_Execution_Log_Cleanup]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[ETL_Execution_Log_Cleanup]
GO
CREATE   PROCEDURE [Audit].[ETL_Execution_Log_Cleanup]
AS
BEGIN
    DECLARE @Temp_Rows INT;
    DECLARE @Log_Rows  INT;

    -- Count pending updates
    SELECT @Temp_Rows = COUNT(*)
    FROM Audit.Process_Execution_Temp;

    IF @Temp_Rows > 0
    BEGIN
        -- Apply updates from temp table to main execution log
        UPDATE LogTbl
        SET     Status           = TmpTbl.Status
              , End_Time         = TmpTbl.End_Time
              , Duration_Seconds = CASE TmpTbl.Status 
                                      WHEN 'ABORTED' THEN -1 
                                      ELSE DATEDIFF(SECOND, LogTbl.Start_Time, TmpTbl.End_Time) 
                                    END
              , Num_Of_Records   = TmpTbl.Rows_Inserted + TmpTbl.Rows_Updated + TmpTbl.Rows_Deleted
              , Error_Message    = TmpTbl.Error_Message
              , Process_Result   = TmpTbl.Process_Result
              , Rows_Inserted    = TmpTbl.Rows_Inserted
              , Rows_Updated     = TmpTbl.Rows_Updated
              , Rows_Deleted     = TmpTbl.Rows_Deleted
        FROM Audit.Process_Execution_Log AS LogTbl
        JOIN Audit.Process_Execution_Temp AS TmpTbl
              ON LogTbl.Run_UUID = TmpTbl.Run_UUID;

        -- Check how many rows were updated
        SELECT @Log_Rows = @@ROWCOUNT;

        -- If all updates applied, clear temp table
        IF @Log_Rows = @Temp_Rows
            TRUNCATE TABLE Audit.Process_Execution_Temp;
    END
END;
GO
