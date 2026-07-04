--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Practitioner_Contribution] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Practitioner_Contribution
--  Author           :  AIH
--  Initial Date     :  2026-07-04
--  History          :
--    *01     2026-07-04  AIH  Initial release (practitioner contribution)
--  Notes:
--    Grain  : Practitioner x Site x Invoice-date x Tenant.
--    Pattern: Full DELETE + INSERT each run. pk via ROW_NUMBER() (no IDENTITY).
--    Production = SUM(Fact_Invoice_Items.Total_Price). Associate_Pct from the
--    admin-entered Input.Practitioner_Pay (NULL/absent -> 0, i.e. keeps full
--    production). Associate_Pay = Production * Pct/100; Contribution = Production - Pay.
--    GOLD_AGG: reads Gold.Fact_Invoice_Items so the Gold->Agg rule orders it after that
--    fact. NHS/UDA income is not invoice-priced -> understated for NHS-heavy work (TODO).
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Aggregate_Practitioner_Contribution
--               @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Practitioner_Contribution]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Practitioner_Contribution]
(
      @Mode        VARCHAR(100)     = 'TEST'
    , @Logging     smallint         = 1
    , @Run_UUID    UNIQUEIDENTIFIER = NULL
    , @Run_Inserts BIGINT OUT
    , @Run_Updates BIGINT OUT
    , @Run_Deletes BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        -- ── Gross production per practitioner x site x invoice-date ───────────
        SELECT
            ii.Tenant_ID,
            ii.fk_Practitioner,
            ii.fk_Practice_Site,
            ii.fk_Date_Invoice                      AS fk_Date,
            SUM(ISNULL(ii.Total_Price, 0))          AS Production
        INTO #prod
        FROM Gold.Fact_Invoice_Items ii
        WHERE ii.fk_Practitioner IS NOT NULL AND ii.fk_Practitioner > 0
        GROUP BY ii.Tenant_ID, ii.fk_Practitioner, ii.fk_Practice_Site, ii.fk_Date_Invoice;

        -- ── Full rebuild: apply each practitioner's associate % ───────────────
        DELETE FROM Gold.Aggregate_Practitioner_Contribution;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Aggregate_Practitioner_Contribution (
            pk_Practitioner_Contribution, Tenant_ID, fk_Practitioner, fk_Practice_Site, fk_Date,
            Production, Associate_Pct, Associate_Pay, Contribution, DW_Created_At, DW_Updated_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY p.Tenant_ID, p.fk_Practitioner, p.fk_Date),
            p.Tenant_ID,
            p.fk_Practitioner,
            p.fk_Practice_Site,
            p.fk_Date,
            p.Production,
            pp.Associate_Pct,
            CAST(p.Production * ISNULL(pp.Associate_Pct, 0) / 100.0 AS DECIMAL(18,2))       AS Associate_Pay,
            CAST(p.Production * (1 - ISNULL(pp.Associate_Pct, 0) / 100.0) AS DECIMAL(18,2)) AS Contribution,
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #prod p
        LEFT JOIN Gold.Dim_Practitioners dp
            ON dp.pk_Practitioner = p.fk_Practitioner AND dp.Tenant_ID = p.Tenant_ID
        LEFT JOIN Input.Practitioner_Pay pp
            ON pp.Tenant_ID = p.Tenant_ID AND pp.Practitioner_ID = dp.Practitioner_ID;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #prod;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes
END
GO
