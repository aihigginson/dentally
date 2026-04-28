/****** Object:  StoredProcedure [Audit].[Meta_Refresh_Record_Count]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[Meta_Refresh_Record_Count]
GO
CREATE   PROCEDURE [Audit].[Meta_Refresh_Record_Count]
(
      @Layer         VARCHAR(255)
    , @Logging       smallint = 1
    , @Run_UUID      UNIQUEIDENTIFIER
    , @Run_Inserts   INT OUT
    , @Run_Updates   INT OUT
    , @Run_Deletes   INT OUT
)
AS
BEGIN
    DECLARE @Proc_Name      SYSNAME        = '[Audit].[Refresh_Record_Count]';
    DECLARE @Row_Num        INT            = 0;
    DECLARE @Cur_Rows       INT            = 0;
    DECLARE @Medallion      VARCHAR(255);
    DECLARE @Database       VARCHAR(255);
    DECLARE @Schema         VARCHAR(255);
    DECLARE @Table          VARCHAR(255);
    DECLARE @Old_Rows       INT;
    DECLARE @New_Rows       INT;
    DECLARE @Old_Date       DATETIME2(6);
    DECLARE @New_Date       DATETIME2(6);
    DECLARE @Target         VARCHAR(1000);
    DECLARE @Dyn_SQL        NVARCHAR(1000);
    DECLARE @Dyn_Prm        NVARCHAR(1000);
    DECLARE @Message        VARCHAR(1000);
    DECLARE @Tab_UUID       UNIQUEIDENTIFIER;

    BEGIN TRY

        SELECT  ROW_NUMBER() OVER (ORDER BY TP.[Database_Name], TP.[Schema_Name], TP.[Table_Name]) AS [Row_Number]
              , TP.[Medallion_Layer]
              , TP.[Database_Name]
              , TP.[Schema_Name]
              , TP.[Table_Name]
              , TP.[Record_Count]     AS [Old_Rows]
              , TP.[Refresh_Date]     AS [Old_Date]
              , TP.[Meta_Table_UUID]
        INTO #Cur_Tables
        FROM Audit.Meta_Table_Profile AS TP
        WHERE TP.[Medallion_Layer] = @Layer;

        SET @Cur_Rows = @@ROWCOUNT;

        WHILE @Row_Num < @Cur_Rows
        BEGIN
            SET @Row_Num += 1;

            SELECT  @Medallion = [Medallion_Layer]
                  , @Database  = [Database_Name]
                  , @Schema    = [Schema_Name]
                  , @Table     = [Table_Name]
                  , @Old_Rows  = [Old_Rows]
                  , @Old_Date  = [Old_Date]
                  , @Tab_UUID  = [Meta_Table_UUID]
            FROM #Cur_Tables
            WHERE [Row_Number] = @Row_Num;

            SET @Target = QUOTENAME(@Database) + '.' + QUOTENAME(@Schema) + '.' + QUOTENAME(@Table);

            IF OBJECT_ID(@Target, 'U') IS NULL
            BEGIN
                SET @Message = 'Table ' + @Target + ' does not exist. Skipping...';
                IF @Logging > 0 
                    EXEC Audit.ETL_Log_Message @Run_UUID, @Proc_Name, @Message, 3;
            END
            ELSE
            BEGIN
                SET @Dyn_SQL = N'SELECT @RC = COUNT(1) FROM ' + @Target;
                SET @Dyn_Prm = N'@RC INT OUT';

                EXEC sp_executesql @Dyn_SQL, @Dyn_Prm, @RC = @New_Rows OUTPUT;

                SET @New_Rows = ISNULL(@New_Rows, 0);
                SET @New_Date = SYSDATETIME();

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

                UPDATE Audit.Meta_Table_Profile
                SET     Record_Count   = @New_Rows
                      , Previous_Count = @Old_Rows
                      , Refresh_Date   = @New_Date
                WHERE Meta_Table_UUID = @Tab_UUID;

                SET @Run_Updates = @Run_Updates + @@ROWCOUNT;

                IF @New_Rows < ISNULL(@Old_Rows, 0)
                BEGIN
                    SET @Message = 'Table ' + @Target + ' has fewer rows than before. Now: '
                                 + FORMAT(@New_Rows, 'N0') + '; Prev: ' + FORMAT(@Old_Rows, 'N0');

                    IF @Logging > 0 
                        EXEC Audit.ETL_Log_Message @Run_UUID, @Proc_Name, @Message, 2;
                END
                ELSE
                BEGIN
                    SET @Message = 'Table ' + @Target + ' rowcount: ' + FORMAT(@New_Rows, 'N0');

                    IF @Logging > 0 
                        EXEC Audit.ETL_Log_Message @Run_UUID, @Proc_Name, @Message, 1;
                END
            END
        END

        DROP TABLE #Cur_Tables;

    END TRY

    BEGIN CATCH
        THROW;
    END CATCH

    RETURN;
END;
GO
