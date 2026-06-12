--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_NHS_Contract_Week] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_NHS_Contract_Week
--  Author           :  AIH
--  Initital Date    :  12/06/2026
--  History          :
--    *01     12/06/2026  AIH Initial Release
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_NHS_Contract_Week @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
--  Pro-rates each NHS contract's annual UDA target across financial weeks
--  using England working days (Mon-Fri, excl. bank holidays).
--  UDA value per week = UDA_Target * (working_days_in_week / total_working_days_in_year).
--  Grain: one row per active NHS contract per financial week it covers.
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_NHS_Contract_Week]    Script Date: 12/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_NHS_Contract_Week]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_NHS_Contract_Week]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       SMALLINT         = 1
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
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        -- Total England working days per financial year
        SELECT
            Financial_Year,
            CAST(COUNT(*) AS SMALLINT) AS Total_Working_Days
        INTO #fy_wd
        FROM Gold.Dim_Date
        WHERE Is_Working_Day_England = 1
        GROUP BY Financial_Year;

        -- Working days per contract per financial week
        -- Join each contract to every working day within its date range,
        -- then aggregate to financial week grain.
        SELECT
            c.pk_NHS_Contract,
            c.Tenant_ID,
            c.UDA_Target,
            d.Financial_Year,
            d.Financial_Week,
            CAST(COUNT(*) AS SMALLINT) AS Working_Days_In_Week
        INTO #cw
        FROM Gold.Dim_NHS_Contracts c
        JOIN Gold.Dim_Date d
            ON d.Full_Date >= c.Start_Date
           AND d.Full_Date <= c.End_Date
           AND d.Is_Working_Day_England = 1
        WHERE c.pk_NHS_Contract > 0
          AND c.UDA_Target > 0
          AND c.Start_Date IS NOT NULL
          AND c.End_Date   IS NOT NULL
        GROUP BY
            c.pk_NHS_Contract,
            c.Tenant_ID,
            c.UDA_Target,
            d.Financial_Year,
            d.Financial_Week;

        -- pk_Date for the week-commencing Monday of each financial year/week
        SELECT DISTINCT
            Financial_Year,
            Financial_Week,
            DATEDIFF(DAY, '19991231', Week_Commencing_Date) AS fk_Date_Week_Start
        INTO #wk
        FROM Gold.Dim_Date;

        -- Full rebuild
        DELETE FROM Gold.Fact_NHS_Contract_Week;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Fact_NHS_Contract_Week (
            pk_NHS_Contract_Week,
            fk_NHS_Contract,
            fk_Date_Week_Start,
            Tenant_ID,
            Financial_Year,
            Financial_Week,
            Working_Days_In_Week,
            Total_Working_Days_In_Year,
            Pro_Rata_UDA_Target,
            DW_Created_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY cw.pk_NHS_Contract, cw.Financial_Year, cw.Financial_Week),
            cw.pk_NHS_Contract,
            wk.fk_Date_Week_Start,
            cw.Tenant_ID,
            cw.Financial_Year,
            cw.Financial_Week,
            cw.Working_Days_In_Week,
            fy.Total_Working_Days,
            cw.UDA_Target
                * CAST(cw.Working_Days_In_Week AS DECIMAL(18,4))
                / NULLIF(fy.Total_Working_Days, 0),
            CAST(SYSUTCDATETIME() AS DATETIME2(3))
        FROM #cw        cw
        JOIN #fy_wd     fy ON fy.Financial_Year = cw.Financial_Year
        JOIN #wk        wk ON wk.Financial_Year = cw.Financial_Year
                           AND wk.Financial_Week = cw.Financial_Week;

        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #fy_wd;
        DROP TABLE #cw;
        DROP TABLE #wk;

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
