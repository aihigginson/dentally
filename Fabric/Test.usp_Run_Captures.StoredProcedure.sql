--------------------------------------------------------------------
--  Stored Procedure :  Test.usp_Run_Captures
--  Author           :  AIH
--  Initial Date     :  13/06/2026
--  History          :
--    *01     13/06/2026  AIH Initial Release
--  Purpose          :  Execute every active Test.Metric_Definition row and
--                      write the scalar result into Test.Capture_Current.
--                      Capture_Current is fully replaced each run. A metric
--                      whose SQL errors is recorded with a NULL value and the
--                      error text, so one bad metric never aborts the run.
--  To Run           :  EXEC Test.usp_Run_Captures @Run_Tag = 'optional-label'
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Test].[usp_Run_Captures]
GO
CREATE   PROCEDURE [Test].[usp_Run_Captures]
(
    @Run_Tag varchar(200) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now         datetime2(3);
    DECLARE @Row_Num     int            = 0;
    DECLARE @Cur_Rows    int            = 0;
    DECLARE @Metric_Name varchar(200);
    DECLARE @SQL_Text    varchar(4000);
    DECLARE @Dyn         nvarchar(4000);
    DECLARE @Val         decimal(38,4);
    DECLARE @Err         varchar(4000);

    SET @Now = SYSDATETIME();

    BEGIN TRY

        -- Start a clean run.
        TRUNCATE TABLE Test.Capture_Current;

        SELECT  ROW_NUMBER() OVER (ORDER BY Metric_Name) AS Row_Number
              , Metric_Name
              , SQL_Text
        INTO #Metrics
        FROM Test.Metric_Definition
        WHERE Is_Active = 1;

        SET @Cur_Rows = @@ROWCOUNT;

        WHILE @Row_Num < @Cur_Rows
        BEGIN
            SET @Row_Num = @Row_Num + 1;

            SELECT  @Metric_Name = Metric_Name
                  , @SQL_Text    = SQL_Text
            FROM #Metrics
            WHERE Row_Number = @Row_Num;

            SET @Val = NULL;
            SET @Err = NULL;

            -- Wrap the metric SQL as a scalar subquery so any single-value
            -- SELECT (COUNT / SUM / etc.) lands in the output parameter.
            BEGIN TRY
                SET @Dyn = N'SELECT @out = (' + CAST(@SQL_Text AS nvarchar(4000)) + N')';
                EXEC sp_executesql @Dyn, N'@out decimal(38,4) OUTPUT', @out = @Val OUTPUT;
            END TRY
            BEGIN CATCH
                SET @Err = LEFT(ERROR_MESSAGE(), 4000);
                SET @Val = NULL;
            END CATCH

            INSERT INTO Test.Capture_Current
                (Metric_Name, Value, Captured_At, Run_Tag, Error_Message)
            VALUES
                (@Metric_Name, @Val, @Now, @Run_Tag, @Err);
        END

        DROP TABLE #Metrics;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH

    RETURN;
END;
GO
