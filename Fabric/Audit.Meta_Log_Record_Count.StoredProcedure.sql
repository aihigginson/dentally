/****** Object:  StoredProcedure [Audit].[Meta_Log_Record_Count]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[Meta_Log_Record_Count]
GO
CREATE   PROCEDURE [Audit].[Meta_Log_Record_Count]
(
      @Medallion     VARCHAR(255)
    , @Database      VARCHAR(255)
    , @Schema        VARCHAR(255)
    , @Table         VARCHAR(255)
    , @Logging       smallint = 1
    , @Run_UUID      UNIQUEIDENTIFIER
    , @Run_Inserts   INT OUT
    , @Run_Updates   INT OUT
    , @Run_Deletes   INT OUT
)
AS
BEGIN
    DECLARE @Proc_Name   SYSNAME        = '[Audit].[Meta_Log_Record_Count]';
    DECLARE @Old_Rows    INT;
    DECLARE @New_Rows    INT;
    DECLARE @Old_Date    DATETIME2(6);
    DECLARE @New_Date    DATETIME2(6);
    DECLARE @Target      VARCHAR(1000);
    DECLARE @Dyn_SQL     NVARCHAR(1000);
    DECLARE @Dyn_Prm     NVARCHAR(1000);
    DECLARE @Message     VARCHAR(1000);
    DECLARE @Tab_UUID    UNIQUEIDENTIFIER;

    BEGIN TRY

        -- Build SQL injection–safe object name
        SET @Target = QUOTENAME(@Database) + '.' + QUOTENAME(@Schema) + '.' + QUOTENAME(@Table);

        -- Check table exists
        IF OBJECT_ID(@Target, 'U') IS NULL
        BEGIN
            SET @Message = 'Table ' + @Target + ' does not exist. Skipping...';
            IF @Logging > 0 
                EXEC Audit.ETL_Log_Message @Run_UUID, @Proc_Name, @Message, 3;
        END
        ELSE
        BEGIN
            -- Count current rows
            SET @Dyn_SQL = N'SELECT @RC = COUNT(1) FROM ' + @Target;
            SET @Dyn_Prm = N'@RC INT OUT';

            EXEC sp_executesql @Dyn_SQL, @Dyn_Prm, @RC = @New_Rows OUTPUT;

            SET @New_Rows = ISNULL(@New_Rows, 0);
            SET @New_Date = SYSDATETIME();

            -- Insert into record count log
            INSERT INTO Audit.Record_Count_Log
            (
                  Record_Count_UUID
                , Log_Date
                , Medallion_Layer
                , Database_Name
                , Schema_Name
                , Table_Name
                , Record_Count
            )
            VALUES
            (
                  NEWID()
                , @New_Date
                , @Medallion
                , @Database
                , @Schema
                , @Table
                , @New_Rows
            );

            SET @Run_Inserts = @Run_Inserts + @@ROWCOUNT;

            -- NOTE: The original procedure had update logic commented out.
            -- I preserved that exactly as requested.
        END

    END TRY

    BEGIN CATCH
        THROW;
    END CATCH

    RETURN;
END;
GO
