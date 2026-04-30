--------------------------------------------------------------------
--  Stored Procedure :  Audit.ETL_Finish_Run
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Audit.ETL_Finish_Run @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Audit].[ETL_Finish_Run]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[ETL_Finish_Run]
GO
CREATE   PROCEDURE [Audit].[ETL_Finish_Run]
(
      @Run_UUID       VARCHAR(36)
    , @Run_Status     VARCHAR(50)  = 'FINISHED'
    , @Rows_Inserted  INT          = 0
    , @Rows_Updated   INT          = 0
    , @Rows_Deleted   INT          = 0
    , @Result         VARCHAR(1000) = NULL
    , @Error          VARCHAR(4000) = NULL
)
AS
BEGIN
    DECLARE @Run_Finished     DATETIME2(6) = SYSDATETIME();
    DECLARE @Result_Message   VARCHAR(1000) = ISNULL(@Result, @Run_Status + ' at ' + CONVERT(VARCHAR, @Run_Finished, 126));

    DECLARE @Process_Result   VARCHAR(4000) =
          '{ "Inserted": ' + CONVERT(VARCHAR, ISNULL(@Rows_Inserted, -1))
        + ', "Updated": '  + CONVERT(VARCHAR, ISNULL(@Rows_Updated, -1))
        + ', "Deleted": '  + CONVERT(VARCHAR, ISNULL(@Rows_Deleted, -1))
        + ', "Message": "' + @Result_Message + '" }';

    DECLARE @UUID             UNIQUEIDENTIFIER = CONVERT(UNIQUEIDENTIFIER, @Run_UUID);

    DECLARE @RetVal           INT = -1;
    DECLARE @Except           INT = 0;
    DECLARE @Tries            INT = 0;
    DECLARE @MaxTry           INT = 3;
    DECLARE @Wait             VARCHAR(8) = '00:00:05';
    DECLARE @LogMsg           VARCHAR(1000);

    WHILE @Tries < @MaxTry
    BEGIN
        SET @Tries = @Tries + 1;

        SET @LogMsg = 'Try # ' + CONVERT(VARCHAR(1), @Tries);
        EXEC Audit.ETL_Log_Message @UUID, 'ETL_Finish_Run', @LogMsg, 0;

        BEGIN TRY
            UPDATE Audit.Process_Execution_Log
            SET     Status           = @Run_Status
                  , End_Time         = @Run_Finished
                  , Duration_Seconds = CASE @Run_Status WHEN 'ABORTED' THEN -1 ELSE DATEDIFF(SECOND, Start_Time, @Run_Finished) END
                  , Num_Of_Records   = @Rows_Inserted + @Rows_Updated + @Rows_Deleted
                  , Error_Message    = @Error
                  , Process_Result   = @Process_Result
                  , Rows_Inserted    = @Rows_Inserted
                  , Rows_Updated     = @Rows_Updated
                  , Rows_Deleted     = @Rows_Deleted
            WHERE Run_UUID = @UUID;

            SET @RetVal = @@ROWCOUNT;
            RETURN @RetVal;
        END TRY

        BEGIN CATCH
            SET @Except = ERROR_NUMBER();
            SET @LogMsg = Audit.ETL_Error_Handler();
            EXEC Audit.ETL_Log_Message @UUID, 'ETL_Finish_Run', @LogMsg, 3;

            IF @Except NOT IN (24556, 24707)
                THROW;

            IF @Tries = @MaxTry
            BEGIN
                INSERT INTO Audit.Process_Execution_Temp
                (
                      Run_UUID
                    , Status
                    , End_Time
                    , Num_Of_Records
                    , Error_Message
                    , Process_Result
                    , Rows_Inserted
                    , Rows_Updated
                    , Rows_Deleted
                )
                VALUES
                (
                      @UUID
                    , @Run_Status
                    , @Run_Finished
                    , @Rows_Inserted + @Rows_Updated + @Rows_Deleted
                    , @Error
                    , @Process_Result
                    , @Rows_Inserted
                    , @Rows_Updated
                    , @Rows_Deleted
                );
            END
        END CATCH;

        WAITFOR DELAY @Wait;
    END
END;
GO
