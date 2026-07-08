--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Date] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Date
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     27/05/2026  AIH Financial_Year_Name format changed from 'FY2024/25' to 'FY 2024-25'
--    *03     29/05/2026  AIH Add Calendar_Year_Week, Week_Commencing_Date, Week_Ending_Date,
--                            Month_Commencing_Date, Month_Ending_Date
--    *04     12/06/2026  AIH Add Is_Working_Day_England (Mon-Fri excl. England/Wales bank holidays)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Date @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Date]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Date]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Date]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    -- Local counters
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;    
--    DECLARE @Run_Inserts   BIGINT  , @Run_Updates   BIGINT , @Run_Deletes   BIGINT 
    -- Example variable
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************
    SET NOCOUNT ON  
    -- Drop and recreate the table
    IF OBJECT_ID('Gold.Dim_Date', 'U') IS NOT NULL
        SELECT @My_Deletes = COUNT(*) FROM Gold.Dim_Date
    DROP TABLE IF EXISTS Gold.Dim_Date;

    CREATE TABLE Gold.Dim_Date (
        -- Surrogate Key
        pk_Date                         INT             NOT NULL,

        -- Date
        Full_Date                       DATE            NOT NULL,

        -- Calendar Day
        Day_Name                        VARCHAR(10)     NOT NULL,   -- 'Monday'
        Day_Of_Week                     smallint         NOT NULL,   -- 1 (Sun) - 7 (Sat)
        Day_Of_Month                    smallint         NOT NULL,   -- 1-31
        Day_Of_Year                     SMALLINT        NOT NULL,   -- 1-366

        -- Calendar Week
        Week_Of_Year                    smallint         NOT NULL,   -- ISO week 1-53
        Week_Of_Month                   smallint         NOT NULL,   -- 1-5
        Calendar_Year_Week              INT              NOT NULL,   -- e.g. 202523
        Week_Commencing_Date            DATE             NOT NULL,   -- Monday of the week
        Week_Ending_Date                DATE             NOT NULL,   -- Sunday of the week

        -- Calendar Month
        Month_Number                    smallint         NOT NULL,   -- 1-12
        Month_Name                      VARCHAR(10)     NOT NULL,   -- 'January'
        Month_Name_Short                VARCHAR(3)         NOT NULL,   -- 'Jan'
        Month_Year                      VARCHAR(10)         NOT NULL,   -- 'Jan-2024'
        Month_Commencing_Date           DATE             NOT NULL,   -- 1st of the month
        Month_Ending_Date               DATE             NOT NULL,   -- Last day of the month

        -- Calendar Quarter
        Calendar_Quarter                smallint         NOT NULL,   -- 1-4
        Calendar_Quarter_Name           VARCHAR(2)         NOT NULL,   -- 'Q1'

        -- Calendar Year
        Calendar_Year                   SMALLINT        NOT NULL,   -- 2000-2040
        Calendar_Year_Month             INT             NOT NULL,   -- 202401
        Calendar_Year_Quarter           VARCHAR(7)         NOT NULL,   -- '2024-Q1'

        -- Relative Calendar (0 = today, -1 = yesterday, etc.)
        Relative_Day                    INT             NOT NULL,
        Relative_Week                   INT             NOT NULL,
        Relative_Month                  INT             NOT NULL,
        Relative_Quarter                INT             NOT NULL,
        Relative_Year                   INT             NOT NULL,

        -- Recency band relative to today (age-band slicer). Labels DON'T sort alphabetically
        -- ('Last 3 Months' starts 'L' -> sorts after the numeric ones), so pair with the numeric
        -- Recency_Band_Sort and set it as the "Sort by column" in PBI.
        Recency_Band                    VARCHAR(20)     NOT NULL,
        Recency_Band_Sort               SMALLINT        NOT NULL,

        -- Financial Year (April-March)
        Financial_Year                  SMALLINT        NOT NULL,   -- Starting year, e.g. 2024 for FY2024/25
        Financial_Year_Name             CHAR(10)        NOT NULL,   -- 'FY 2024-25'
        Financial_Quarter               smallint         NOT NULL,   -- 1-4
        Financial_Quarter_Name          VARCHAR(11)     NOT NULL,   -- 'FY2024 Q1'
        Financial_Month                 smallint         NOT NULL,   -- 1-12 (1 = April)
        Financial_Month_Name            VARCHAR(20)     NOT NULL,   -- 'FY2024 Apr'
        Financial_Week                  smallint         NOT NULL,   -- 1-53 within financial year
        Financial_Day_Of_Year           SMALLINT        NOT NULL,   -- Day number within financial year

        -- Relative Financial
        Relative_Financial_Day          INT             NOT NULL,
        Relative_Financial_Week         INT             NOT NULL,
        Relative_Financial_Month        INT             NOT NULL,
        Relative_Financial_Quarter      INT             NOT NULL,
        Relative_Financial_Year         INT             NOT NULL,

        -- Flags
        Is_Weekend                      BIT             NOT NULL,
        Is_Leap_Year                    BIT             NOT NULL,
        Is_England_Wales_Bank_Holiday   BIT             NOT NULL,
        Is_Scotland_Bank_Holiday        BIT             NOT NULL,
        Is_Working_Day_England          BIT             NOT NULL
    );

    -- -------------------------------------------------------
    -- Populate (set-based: single INSERT replaces WHILE loop)
    -- -------------------------------------------------------
    DECLARE @Today               DATE     = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @Today_FY_Start_Year SMALLINT = CASE WHEN MONTH(@Today) >= 4 THEN YEAR(@Today) ELSE YEAR(@Today) - 1 END;
    DECLARE @Today_FY_Start      DATE     = DATEFROMPARTS(@Today_FY_Start_Year, 4, 1);
    DECLARE @Today_Week_Start    DATE     = DATEADD(DAY, -(DATEPART(WEEKDAY, @Today) + 5) % 7, @Today);
    DECLARE @Today_FY_Start_Mon  DATE     = DATEADD(DAY, -(DATEPART(WEEKDAY, @Today_FY_Start) + 5) % 7, @Today_FY_Start);
    DECLARE @Today_Fin_Month     SMALLINT = CASE WHEN MONTH(@Today) >= 4 THEN MONTH(@Today) - 3 ELSE MONTH(@Today) + 9 END;
    DECLARE @Today_Fin_Qtr       SMALLINT = ((@Today_Fin_Month - 1) / 3) + 1;

    WITH
    -- 10^5 integers via CROSS JOIN of digit tables — covers the full date range
    Digits AS (
        SELECT x FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) v(x)
    ),
    Numbers AS (
        SELECT a.x + b.x*10 + c.x*100 + d.x*1000 + e.x*10000 AS n
        FROM Digits a CROSS JOIN Digits b CROSS JOIN Digits c
                      CROSS JOIN Digits d CROSS JOIN Digits e
    ),
    Dates AS (
        SELECT CAST(DATEADD(DAY, n, '2000-01-01') AS DATE) AS d
        FROM Numbers
        WHERE DATEADD(DAY, n, '2000-01-01') <= '2040-12-31'
    ),
    -- First layer: simple per-date derivations used in multiple columns
    D1 AS (
        SELECT
            d,
            YEAR(d)  AS yr,
            MONTH(d) AS mo,
            DAY(d)   AS dy,
            CASE WHEN MONTH(d) >= 4 THEN YEAR(d)      ELSE YEAR(d) - 1  END AS fy_yr,
            CASE WHEN MONTH(d) >= 4 THEN MONTH(d) - 3 ELSE MONTH(d) + 9 END AS fin_mo,
            DATEADD(DAY, -(DATEPART(WEEKDAY, d) + 5) % 7, d)               AS row_week_mon
        FROM Dates
    ),
    -- Second layer: values that depend on first layer
    D2 AS (
        SELECT
            d.*,
            (mo - 1) / 3 + 1                                               AS cal_qtr,
            ((fin_mo - 1) / 3) + 1                                         AS fin_qtr,
            DATEFROMPARTS(yr, mo, 1)                                        AS month_start,
            DATEFROMPARTS(fy_yr, 4, 1)                                      AS fy_start
        FROM D1 d
    ),
    -- Third layer: values that depend on fy_start
    D3 AS (
        SELECT
            d.*,
            DATEADD(DAY, -(DATEPART(WEEKDAY, fy_start) + 5) % 7, fy_start) AS fy_start_mon
        FROM D2 d
    )
    INSERT INTO Gold.Dim_Date (
        pk_Date,
        Full_Date,
        Day_Name, Day_Of_Week, Day_Of_Month, Day_Of_Year,
        Week_Of_Year, Week_Of_Month, Calendar_Year_Week, Week_Commencing_Date, Week_Ending_Date,
        Month_Number, Month_Name, Month_Name_Short, Month_Year, Month_Commencing_Date, Month_Ending_Date,
        Calendar_Quarter, Calendar_Quarter_Name,
        Calendar_Year, Calendar_Year_Month, Calendar_Year_Quarter,
        Relative_Day, Relative_Week, Relative_Month, Relative_Quarter, Relative_Year,
        Recency_Band, Recency_Band_Sort,
        Financial_Year, Financial_Year_Name,
        Financial_Quarter, Financial_Quarter_Name,
        Financial_Month, Financial_Month_Name,
        Financial_Week, Financial_Day_Of_Year,
        Relative_Financial_Day, Relative_Financial_Week, Relative_Financial_Month,
        Relative_Financial_Quarter, Relative_Financial_Year,
        Is_Weekend, Is_Leap_Year, Is_England_Wales_Bank_Holiday, Is_Scotland_Bank_Holiday,
        Is_Working_Day_England
    )
    SELECT
        DATEDIFF(DAY, '19991231', d),
        d,

        -- Day
        DATENAME(WEEKDAY, d),
        DATEPART(WEEKDAY, d),
        dy,
        DATEPART(DAYOFYEAR, d),

        -- Week
        DATEPART(ISO_WEEK, d),
        DATEDIFF(WEEK, DATEADD(DAY, -(DATEPART(WEEKDAY, month_start) + 5) % 7, month_start), d) + 1,
        yr * 100 + DATEPART(ISO_WEEK, d),
        row_week_mon,
        DATEADD(DAY, 6, row_week_mon),

        -- Month
        mo,
        DATENAME(MONTH, d),
        LEFT(DATENAME(MONTH, d), 3),
        LEFT(DATENAME(MONTH, d), 3) + '-' + CAST(yr AS CHAR(4)),
        month_start,
        CAST(EOMONTH(d) AS DATE),

        -- Quarter
        cal_qtr,
        'Q' + CAST(cal_qtr AS CHAR(1)),

        -- Year
        yr,
        yr * 100 + mo,
        CAST(yr AS CHAR(4)) + '-Q' + CAST(cal_qtr AS CHAR(1)),

        -- Relative Calendar
        DATEDIFF(DAY,     @Today,             d),
        DATEDIFF(WEEK,    @Today_Week_Start,  row_week_mon),
        DATEDIFF(MONTH,   @Today,             d),
        DATEDIFF(QUARTER, @Today,             d),
        DATEDIFF(YEAR,    @Today,             d),

        -- Recency band (days into the past, 30d = 1 month -> 90 / 180 / 360). Future dates get
        -- their own bucket so the column stays NOT NULL for a generic date dim; a past-only field
        -- like Last_Activity_Date never lands there.
        CASE
            WHEN DATEDIFF(DAY, d, @Today) < 0   THEN 'Future'
            WHEN DATEDIFF(DAY, d, @Today) <= 90  THEN 'Last 3 Months'
            WHEN DATEDIFF(DAY, d, @Today) <= 180 THEN '3-6 Months'
            WHEN DATEDIFF(DAY, d, @Today) <= 360 THEN '6-12 Months'
            ELSE 'Over 12 Months'
        END,
        CASE
            WHEN DATEDIFF(DAY, d, @Today) < 0   THEN 0
            WHEN DATEDIFF(DAY, d, @Today) <= 90  THEN 1
            WHEN DATEDIFF(DAY, d, @Today) <= 180 THEN 2
            WHEN DATEDIFF(DAY, d, @Today) <= 360 THEN 3
            ELSE 4
        END,

        -- Financial Year
        fy_yr,
        'FY ' + CAST(fy_yr AS CHAR(4)) + '-' + RIGHT(CAST(fy_yr + 1 AS CHAR(4)), 2),

        -- Financial Quarter
        fin_qtr,
        'FY' + CAST(fy_yr AS CHAR(4)) + ' Q' + CAST(fin_qtr AS CHAR(1)),

        -- Financial Month
        fin_mo,
        'FY' + CAST(fy_yr AS CHAR(4)) + ' ' + LEFT(DATENAME(MONTH, d), 3),

        -- Financial Week & Day
        DATEDIFF(WEEK, fy_start_mon, d) + 1,
        DATEDIFF(DAY,  fy_start,     d) + 1,

        -- Relative Financial
        DATEDIFF(DAY,  @Today_FY_Start,     fy_start)     + DATEDIFF(DAY,  fy_start,     d) - DATEDIFF(DAY,  @Today_FY_Start,     @Today),
        DATEDIFF(WEEK, @Today_FY_Start_Mon, fy_start_mon) + DATEDIFF(WEEK, fy_start_mon, row_week_mon),
        (fy_yr - @Today_FY_Start_Year) * 12 + fin_mo  - @Today_Fin_Month,
        (fy_yr - @Today_FY_Start_Year) * 4  + fin_qtr - @Today_Fin_Qtr,
        fy_yr - @Today_FY_Start_Year,

        -- Flags
        CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END,
        CASE WHEN (yr % 4 = 0 AND yr % 100 <> 0) OR yr % 400 = 0 THEN 1 ELSE 0 END,
        CAST(0 AS BIT),
        CAST(0 AS BIT),
        CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 0 ELSE 1 END
    FROM D3;

    UPDATE d SET Is_England_Wales_Bank_Holiday = 1 
    FROM Gold.Dim_Date d 
    JOIN Bronze.Bank_Holidays ON Holiday_Date=Full_Date AND Division = 'england-and-wales'

    UPDATE d SET Is_Scotland_Bank_Holiday = 1
    FROM Gold.Dim_Date d
    JOIN Bronze.Bank_Holidays ON Holiday_Date=Full_Date AND Division = 'scotland'

    UPDATE Gold.Dim_Date SET Is_Working_Day_England = 0
    WHERE Is_England_Wales_Bank_Holiday = 1


    SELECT @My_Inserts = COUNT(*) FROM Gold.Dim_Date
        --*********************************
        --**** Procedure logic ends    ****
        --*********************************


    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Inserts  


END;

GO
