--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Affiliate_Payment_Lines] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Affiliate_Payment_Lines
--  Author           :  AIH
--  Initial Date     :  24/09/2026
--  History          :
--    *01     24/09/2026  AIH  Initial Release (V182)
--    *02     24/09/2026  AIH  V183: re-grained to affiliate x practice x month. It was built at
--                             subscription-line grain, which is not what an affiliate is owed on.
--  Notes:
--    Grain  : affiliate x practice x month -- one line of what we owe a partner.
--    Pattern: full rebuild, pk via ROW_NUMBER().
--    Sources: Billing.Invoice_Line (the money), Billing.Credit_Note, Billing.Stripe_Invoice,
--             Gold.Dim_Affiliates, Gold.Dim_Tenants, Audit.Tenants.
--
--    ==> THREE THINGS THAT ARE EASY TO GET WRONG, ALL VERIFIED AGAINST DEV DATA. <==
--
--    1. CREDIT NOTES ARE GROSS; INVOICE LINES ARE NET. Credit_Note.Amount_Pence INCLUDES VAT
--       (dev: 416.80 with 69.47 tax) while Invoice_Line.Value EXCLUDES it (386.80). Clawing
--       commission back on the gross figure takes 20% too much off the affiliate every time.
--       Net is Amount_Pence - Tax_Pence. (Stripe_Invoice.Amount_Pence is NET, unlike Credit_Note
--       -- the source schema disagrees with itself, which is why Invoice_Line is the invoiced
--       figure and neither of those is.)
--
--    2. EARNED ON INVOICING, PAYABLE ON COLLECTION. Commission_Payable stays 0 until Stripe
--       reports the customer actually paid, or a payout funds a partner out of our own pocket
--       against money never collected.
--
--    3. THE RATE COMES OFF THE LINE. Invoice_Line.Affiliate_Commission_Pct is frozen at
--       generation, so re-rating an affiliate cannot restate statements already settled. MAX()
--       over a practice-month reads the one rate those lines were generated with.
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Affiliate_Payment_Lines]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Affiliate_Payment_Lines]
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
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        -- The grain: affiliate x practice x month. The billed users are summed, not carried.
        SELECT il.Affiliate_ID,
               il.Tenant_ID,
               il.Year_Month,
               MAX(il.Affiliate_Commission_Pct)   AS Commission_Pct,
               COUNT(*)                           AS Billed_Users,
               SUM(il.Value)                      AS Invoiced_Net,
               SUM(il.Affiliate_Commission_Value) AS Commission_Accrued
        INTO #src
        FROM [Billing].[Invoice_Line] il
        WHERE il.Affiliate_ID IS NOT NULL
        GROUP BY il.Affiliate_ID, il.Tenant_ID, il.Year_Month;

        -- Credit notes are raised per practice-month, which IS this grain -- so no apportionment
        -- and one rounding. That is the whole reason the figures reconcile exactly.
        SELECT cn.Tenant_ID, cn.Year_Month,
               CAST(SUM(cn.Amount_Pence - ISNULL(cn.Tax_Pence, 0)) / 100.0 AS DECIMAL(10,2))
                   AS Credited_Net
        INTO #credit
        FROM [Billing].[Credit_Note] cn
        GROUP BY cn.Tenant_ID, cn.Year_Month;

        SELECT si.Tenant_ID, si.Year_Month, MAX(si.Status) AS Customer_Invoice_Status
        INTO #inv
        FROM [Billing].[Stripe_Invoice] si
        GROUP BY si.Tenant_ID, si.Year_Month;

        DELETE FROM [Gold].[Fact_Affiliate_Payment_Lines];
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO [Gold].[Fact_Affiliate_Payment_Lines]
            (pk_Affiliate_Payment_Line, fk_Affiliate, fk_Tenant, fk_Date_Month, Tenant_ID,
             Practice_Name, Affiliate_Email, Affiliate_Name, Year_Month, Month_Start,
             Commission_Pct, Billed_Users, Invoiced_Net, Credited_Net, Net_After_Credits,
             Commission_Accrued, Commission_On_Credits, Commission_Due,
             Customer_Invoice_Status, Is_Customer_Paid, Commission_Payable,
             Line_Count, DW_Created_At, DW_Updated_At)
        SELECT
            ROW_NUMBER() OVER (ORDER BY s.Year_Month, s.Affiliate_ID, s.Tenant_ID),
            da.pk_Affiliate,
            dt.pk_Tenant,
            [Gold].[fn_Get_Date_Key](DATEFROMPARTS(s.Year_Month / 100, s.Year_Month % 100, 1)),
            s.Tenant_ID,
            t.Tenant_Name,
            da.Affiliate_Email,
            da.Affiliate_Name,
            s.Year_Month,
            DATEFROMPARTS(s.Year_Month / 100, s.Year_Month % 100, 1),
            s.Commission_Pct,
            s.Billed_Users,
            s.Invoiced_Net,
            ISNULL(c.Credited_Net, 0),
            CAST(s.Invoiced_Net - ISNULL(c.Credited_Net, 0) AS DECIMAL(10,2)),
            s.Commission_Accrued,
            -- Rounded ONCE, at the grain the credit was raised at.
            CAST(ROUND(-ISNULL(c.Credited_Net, 0) * ISNULL(s.Commission_Pct, 0), 2) AS DECIMAL(10,2)),
            -- Derived from that same rounded figure, so the columns add up exactly as printed.
            CAST(s.Commission_Accrued
                 + ROUND(-ISNULL(c.Credited_Net, 0) * ISNULL(s.Commission_Pct, 0), 2) AS DECIMAL(10,2)),
            ISNULL(i.Customer_Invoice_Status, 'not raised'),
            CAST(CASE WHEN i.Customer_Invoice_Status = 'paid' THEN 1 ELSE 0 END AS BIT),
            CAST(CASE WHEN i.Customer_Invoice_Status = 'paid'
                      THEN s.Commission_Accrued
                           + ROUND(-ISNULL(c.Credited_Net, 0) * ISNULL(s.Commission_Pct, 0), 2)
                      ELSE 0 END AS DECIMAL(10,2)),
            1, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src s
        LEFT JOIN #credit c ON c.Tenant_ID = s.Tenant_ID AND c.Year_Month = s.Year_Month
        LEFT JOIN #inv    i ON i.Tenant_ID = s.Tenant_ID AND i.Year_Month = s.Year_Month
        LEFT JOIN [Gold].[Dim_Affiliates] da ON da.bk_Affiliate_ID = s.Affiliate_ID
        LEFT JOIN [Gold].[Dim_Tenants]    dt ON dt.Tenant_ID       = s.Tenant_ID
        LEFT JOIN [Audit].[Tenants]       t  ON t.Tenant_ID        = s.Tenant_ID;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        DROP TABLE #credit;
        DROP TABLE #inv;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes
END
GO
