--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Date_Grouping] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Date_Grouping]    Script Date: 01/05/2026 14:19:54 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:      AI Higginson
-- Create date: 2026-05-01
-- Description: Drops and recreates Gold.Dim_Date_Grouping with named
--              date-range bands and prior-year date key pairs for YoY analysis.
-- =============================================
-- Update History
-- 2026-05-01  AIH  Created
-- =============================================

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Dim_Date_Grouping]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;

    BEGIN TRY
        SET NOCOUNT ON;

        IF OBJECT_ID('Gold.Dim_Date_Grouping', 'U') IS NOT NULL
            SELECT @My_Deletes = COUNT(*) FROM Gold.Dim_Date_Grouping;

        DROP TABLE IF EXISTS Gold.Dim_Date_Grouping;

        CREATE TABLE Gold.Dim_Date_Grouping (
              Date_Grouping         VARCHAR(20) NOT NULL
            , fk_Date               INT         NOT NULL
            , fk_Date_Previous_Year INT         NOT NULL
        );

        INSERT INTO Gold.Dim_Date_Grouping (Date_Grouping, fk_Date, fk_Date_Previous_Year)
        SELECT 'FY 2025-26', d.pk_Date, p.pk_Date
          FROM Gold.Dim_Date d
          JOIN Gold.Dim_Date p ON d.Financial_Year = p.Financial_Year - 1
                               AND d.Financial_Day_Of_Year = p.Financial_Day_Of_Year
         WHERE d.Financial_Year_Name = 'FY 2025-26'
        UNION ALL
        SELECT 'FY 2024-25', d.pk_Date, p.pk_Date
          FROM Gold.Dim_Date d
          JOIN Gold.Dim_Date p ON d.Financial_Year = p.Financial_Year - 1
                               AND d.Financial_Day_Of_Year = p.Financial_Day_Of_Year
         WHERE d.Financial_Year_Name = 'FY 2024-25'
        UNION ALL
        SELECT 'FY 2026-27 (YTD)', d.pk_Date, p.pk_Date
          FROM Gold.Dim_Date d
          JOIN Gold.Dim_Date p ON d.Financial_Year = p.Financial_Year - 1
                               AND d.Financial_Day_Of_Year = p.Financial_Day_Of_Year
         WHERE d.Financial_Year_Name = 'FY 2026-27' AND d.Full_Date <= SYSDATETIME()
        UNION ALL
        SELECT 'Last 12 Months', d.pk_Date, p.pk_Date
          FROM Gold.Dim_Date d
          JOIN Gold.Dim_Date p ON d.Financial_Year = p.Financial_Year - 1
                               AND d.Financial_Day_Of_Year = p.Financial_Day_Of_Year
         WHERE d.Relative_Day BETWEEN -365 AND 0
        UNION ALL
        SELECT 'Last 3 Months', d.pk_Date, p.pk_Date
          FROM Gold.Dim_Date d
          JOIN Gold.Dim_Date p ON d.Financial_Year = p.Financial_Year - 1
                               AND d.Financial_Day_Of_Year = p.Financial_Day_Of_Year
         WHERE d.Relative_Day BETWEEN -90 AND 0;

        SELECT @My_Inserts = COUNT(*) FROM Gold.Dim_Date_Grouping;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;

END;
GO
