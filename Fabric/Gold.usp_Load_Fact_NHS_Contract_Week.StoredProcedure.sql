--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_NHS_Contract_Week] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_NHS_Contract_Week
--  Author           :  AIH
--  Initital Date    :  12/06/2026
--  History          :
--    *01     12/06/2026  AIH Initial Release
--    *02     12/06/2026  AIH Add fk_Practice_Site, fk_Practitioner, Annual_UDA_Target
--                            Two row levels per week:
--                              fk_Practitioner = -1  (contract obligation from NHS contract)
--                              fk_Practitioner = N   (individual allocation from practitioner contract_targets)
--                            These are independent figures; the gap between them is intentional.
--    *03     23/06/2026  AIH Fix week fan-out: Financial_Week (Sun-Sat) straddles two
--                            Monday Week_Commencing_Dates, so the #wk SELECT DISTINCT
--                            emitted 2 rows/week and DOUBLED every target. Collapse to one
--                            Monday per financial week (GROUP BY + MAX(Week_Commencing_Date)).
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_NHS_Contract_Week @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
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

        -- Working days per contract per financial week (via join to all working days in range)
        SELECT
            c.pk_NHS_Contract,
            c.Tenant_ID,
            ISNULL(dps.pk_Practice_Site, -1) AS fk_Practice_Site,
            d.Financial_Year,
            d.Financial_Week,
            CAST(COUNT(*) AS SMALLINT) AS Working_Days_In_Week
        INTO #cw
        FROM Gold.Dim_NHS_Contracts c
        LEFT JOIN Gold.Dim_Practice_Sites dps
            ON  dps.Tenant_ID = c.Tenant_ID
            AND dps.Site_ID   = c.Site_ID
        JOIN Gold.Dim_Date d
            ON  d.Full_Date >= c.Start_Date
            AND d.Full_Date <= c.End_Date
            AND d.Is_Working_Day_England = 1
        WHERE c.pk_NHS_Contract > 0
          AND c.UDA_Target  > 0
          AND c.Start_Date IS NOT NULL
          AND c.End_Date   IS NOT NULL
        GROUP BY
            c.pk_NHS_Contract,
            c.Tenant_ID,
            ISNULL(dps.pk_Practice_Site, -1),
            d.Financial_Year,
            d.Financial_Week;

        -- pk_Date for the week-commencing Monday of each financial year/week.
        -- Dim_Date.Financial_Week is Sun-Sat but Week_Commencing_Date is Monday-based,
        -- so a single financial week straddles TWO Monday weeks. SELECT DISTINCT would
        -- therefore emit 2 rows per (FY, FW) and fan the contract's weekly pro-rata
        -- across both -> the target doubled. Collapse to ONE Monday per financial week
        -- (MAX = the Monday under which the bulk Mon-Sat of the week falls).
        SELECT
            Financial_Year,
            Financial_Week,
            DATEDIFF(DAY, '19991231', MAX(Week_Commencing_Date)) AS fk_Date_Week_Start
        INTO #wk
        FROM Gold.Dim_Date
        GROUP BY Financial_Year, Financial_Week;

        -- Full rebuild
        DELETE FROM Gold.Fact_NHS_Contract_Week;
        SET @My_Deletes = @@ROWCOUNT;

        -- ── Level 1: Contract obligation (fk_Practitioner = -1) ───────────────
        -- Source: Dim_NHS_Contracts.UDA_Target — what the NHS expects the practice
        -- to deliver. Independent of how it is allocated to practitioners.
        INSERT INTO Gold.Fact_NHS_Contract_Week (
            pk_NHS_Contract_Week,
            fk_NHS_Contract, fk_Practice_Site, fk_Practitioner,
            fk_Date_Week_Start,
            Tenant_ID, Financial_Year, Financial_Week,
            Working_Days_In_Week, Total_Working_Days_In_Year,
            Pro_Rata_UDA_Target, Annual_UDA_Target,
            DW_Created_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY cw.pk_NHS_Contract, cw.Financial_Year, cw.Financial_Week),
            cw.pk_NHS_Contract,
            cw.fk_Practice_Site,
            -1,   -- contract obligation level
            wk.fk_Date_Week_Start,
            cw.Tenant_ID,
            cw.Financial_Year,
            cw.Financial_Week,
            cw.Working_Days_In_Week,
            fy.Total_Working_Days,
            c.UDA_Target
                * CAST(cw.Working_Days_In_Week AS DECIMAL(18,4))
                / NULLIF(fy.Total_Working_Days, 0),
            c.UDA_Target,
            CAST(SYSUTCDATETIME() AS DATETIME2(3))
        FROM #cw        cw
        JOIN Gold.Dim_NHS_Contracts c ON c.pk_NHS_Contract = cw.pk_NHS_Contract
        JOIN #fy_wd     fy ON fy.Financial_Year  = cw.Financial_Year
        JOIN #wk        wk ON wk.Financial_Year  = cw.Financial_Year
                           AND wk.Financial_Week = cw.Financial_Week;

        SET @My_Inserts = @@ROWCOUNT;

        -- ── Level 2: Practitioner allocation (fk_Practitioner = N) ───────────
        -- Source: Silver.Practitioner_Contract_Targets — each practitioner's
        -- individual UDA target for the contract. The sum of these does NOT
        -- necessarily equal the contract total; the gap is a planning signal.
        INSERT INTO Gold.Fact_NHS_Contract_Week (
            pk_NHS_Contract_Week,
            fk_NHS_Contract, fk_Practice_Site, fk_Practitioner,
            fk_Date_Week_Start,
            Tenant_ID, Financial_Year, Financial_Week,
            Working_Days_In_Week, Total_Working_Days_In_Year,
            Pro_Rata_UDA_Target, Annual_UDA_Target,
            DW_Created_At
        )
        SELECT
            @My_Inserts + ROW_NUMBER() OVER (ORDER BY cw.pk_NHS_Contract, dp.pk_Practitioner, cw.Financial_Year, cw.Financial_Week),
            cw.pk_NHS_Contract,
            cw.fk_Practice_Site,
            dp.pk_Practitioner,
            wk.fk_Date_Week_Start,
            cw.Tenant_ID,
            cw.Financial_Year,
            cw.Financial_Week,
            cw.Working_Days_In_Week,
            fy.Total_Working_Days,
            pct.UDA_Target
                * CAST(cw.Working_Days_In_Week AS DECIMAL(18,4))
                / NULLIF(fy.Total_Working_Days, 0),
            pct.UDA_Target,
            CAST(SYSUTCDATETIME() AS DATETIME2(3))
        FROM Silver.Practitioner_Contract_Targets pct
        JOIN Gold.Dim_NHS_Contracts c
            ON  c.bk_Contract_ID = pct.bk_Contract_ID
            AND c.Tenant_ID      = pct.Tenant_ID
        JOIN Gold.Dim_Practitioners dp
            ON  dp.Practitioner_ID = pct.bk_Practitioner_ID
            AND dp.Tenant_ID       = pct.Tenant_ID
        JOIN #cw cw
            ON  cw.pk_NHS_Contract = c.pk_NHS_Contract
        JOIN #fy_wd fy ON fy.Financial_Year  = cw.Financial_Year
        JOIN #wk    wk ON wk.Financial_Year  = cw.Financial_Year
                       AND wk.Financial_Week = cw.Financial_Week
        WHERE pct.UDA_Target > 0;

        SET @My_Inserts = @My_Inserts + @@ROWCOUNT;

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
