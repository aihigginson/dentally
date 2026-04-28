/****** Object:  StoredProcedure [Audit].[ETL_Log_Message]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[ETL_Log_Message]
GO
CREATE   PROCEDURE [Audit].[ETL_Log_Message]
(
      @Run_UUID   UNIQUEIDENTIFIER
    , @Process    VARCHAR(255)
    , @Message    VARCHAR(8000)
    , @Level      smallint = 1
)
AS
BEGIN
    -- Logging thresholds
    DECLARE @Log  smallint = 0;   -- Log all messages
    DECLARE @Show smallint = 2;   -- Show warnings and above

    -- Insert all messages above log threshold
    IF @Level >= @Log
    BEGIN
        INSERT INTO Audit.Process_Message_Log
        (
              Message_UUID
            , Run_UUID
            , Process_Name
            , Message_Date
            , Message_Level
            , Message_Text
        )
        VALUES
        (
              NEWID()
            , @Run_UUID
            , @Process
            , SYSDATETIME()
            , @Level
            , @Message
        );
    END;

    -- Print messages above show threshold
    IF @Level >= @Show
    BEGIN
        DECLARE @Print_Level   VARCHAR(10);
        DECLARE @Print_Message VARCHAR(8000);

        SET @Print_Level =
            CASE @Level
                WHEN 1 THEN 'INFORMATION'
                WHEN 2 THEN 'WARNING'
                WHEN 3 THEN 'ERROR'
                ELSE 'MESSAGE'
            END;

        SET @Print_Message = @Print_Level + '::' + @Process + '::' + @Message;

        PRINT @Print_Message;
    END;

    RETURN;
END;
GO
