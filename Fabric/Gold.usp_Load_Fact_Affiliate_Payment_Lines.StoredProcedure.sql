--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Affiliate_Payment_Lines] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Affiliate_Payment_Lines
--  Author           :  AIH
--  Initial Date     :  24/09/2026
--  History          :
--    *01     24/09/2026  AIH  Initial Release (V182)
--  Notes:
--    Grain  : one row per billed user per practice per month.
--    Pattern: full rebuild, pk via ROW_NUMBER() -- as Fact_Patient_At_Risk does.
--    Sources: Billing.Invoice_Line (the money), Billing.Credit_Note, Billing.Stripe_Invoice,
--             Gold.Dim_Affiliates, Gold.Dim_Tenants.
--
--    ==> THREE THINGS THAT ARE EASY TO GET WRONG, ALL VERIFIED AGAINST DEV DATA. <==
--
--    1. CREDIT NOTES ARE GROSS; INVOICE LINES ARE NET. Credit_Note.Amount_Pence INCLUDES VAT
--       (dev: 416.80 with 69.47 tax) while Invoice_Line.Value EXCLUDES it (386.80). Clawing
--       commission back on the gross figure takes 20% too much off the affiliate every time.
--       Net is Amount_Pence - Tax_Pence. (Stripe_Invoice.Amount_Pence is NET, unlike
--       Credit_Note -- the two disagree in the source schema, which is why neither is used as
--       the invoiced figure. Invoice_Line is.)
--
--    2. EARNED ON INVOICING, PAYABLE ON COLLECTION. Commission_Payable stays 0 until Stripe
--       reports the customer actually paid, or a payout funds a partner out of our own pocket
--       against money never collected.
--
--    3. THE RATE COMES OFF THE LINE. Invoice_Line.Affiliate_Commission_Pct is frozen at
--       generation, so re-rating an affiliate cannot restate statements already settled.
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

        -- The month's totals, so a practice-month credit can be shared across its lines.
        SELECT il.Tenant_ID, il.Year_Month, SUM(il.Value) AS Month_Net
        INTO #month
        FROM [Billing].[Invoice_Line] il
        WHERE il.Affiliate_ID IS NOT NULL
        GROUP BY il.Tenant_ID, il.Year_Month;

        SELECT cn.Tenant_ID, cn.Year_Month,
               SUM(cn.Amount_Pence - ISNULL(cn.Tax_Pence, 0)) / 100.0 AS Credited_Net
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
             User_UPN, Display_Name, Profile_Key, Commission_Pct,
             Invoiced_Net, Credited_Net, Net_After_Credits,
             Commission_Accrued, Commission_On_Credits, Commission_Due,
             Customer_Invoice_Status, Is_Customer_Paid, Commission_Payable,
             Line_Count, DW_Created_At, DW_Updated_At)
        SELECT
            ROW_NUMBER() OVER (ORDER BY il.Year_Month, il.Tenant_ID, il.User_UPN),
            da.pk_Affiliate,
            dt.pk_Tenant,
            [Gold].[fn_Get_Date_Key](DATEFROMPARTS(il.Year_Month / 100, il.Year_Month % 100, 1)),
            il.Tenant_ID,
            t.Tenant_Name,
            da.Affiliate_Email,
            da.Affiliate_Name,
            il.Year_Month,
            DATEFROMPARTS(il.Year_Month / 100, il.Year_Month % 100, 1),
            il.User_UPN,
            il.Display_Name,
            il.Profile_Key,
            il.Affiliate_Commission_Pct,
            il.Value,
            cr.Line_Credit,
            CAST(il.Value - cr.Line_Credit AS DECIMAL(10,2)),
            il.Affiliate_Commission_Value,
            -- ==> DUE IS DERIVED FROM THE ROUNDED PARTS, NOT ROUNDED SEPARATELY. <== Rounding
            -- the clawback and the total independently makes them disagree by a penny wherever
            -- the two roundings fall opposite ways -- 11 rows on dev, and the deploy guard
            -- caught it. A statement whose columns do not add up as printed is unusable, so Due
            -- is Accrued plus the SAME rounded figure shown in Commission_On_Credits.
            cr.Commission_Credit,
            CAST(il.Affiliate_Commission_Value + cr.Commission_Credit AS DECIMAL(10,2)),
            ISNULL(i.Customer_Invoice_Status, 'not raised'),
            CAST(CASE WHEN i.Customer_Invoice_Status = 'paid' THEN 1 ELSE 0 END AS BIT),
            CAST(CASE WHEN i.Customer_Invoice_Status = 'paid'
                      THEN il.Affiliate_Commission_Value + cr.Commission_Credit
                      ELSE 0 END AS DECIMAL(10,2)),
            1, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM [Billing].[Invoice_Line] il
        JOIN #month m ON m.Tenant_ID = il.Tenant_ID AND m.Year_Month = il.Year_Month
        CROSS APPLY (
            -- Pro rata: this line's share of the month's credit, by its share of the month's
            -- value. Month_Net is never 0 here -- a month with no value generates no lines.
            SELECT CAST(ROUND(ISNULL(c.Credited_Net, 0)
                              * CASE WHEN m.Month_Net = 0 THEN 0 ELSE il.Value / m.Month_Net END,
                              2) AS DECIMAL(10,2)) AS Line_Credit,
                   -- The clawback, rounded ONCE here so the fact's columns are self-consistent.
                   CAST(ROUND(-ROUND(ISNULL(c.Credited_Net, 0)
                              * CASE WHEN m.Month_Net = 0 THEN 0 ELSE il.Value / m.Month_Net END, 2)
                              * ISNULL(il.Affiliate_Commission_Pct, 0), 2) AS DECIMAL(10,2))
                       AS Commission_Credit
            FROM (SELECT 1 AS x) _
            LEFT JOIN #credit c ON c.Tenant_ID = il.Tenant_ID AND c.Year_Month = il.Year_Month
        ) cr
        LEFT JOIN #inv i ON i.Tenant_ID = il.Tenant_ID AND i.Year_Month = il.Year_Month
        LEFT JOIN [Gold].[Dim_Affiliates] da ON da.bk_Affiliate_ID = il.Affiliate_ID
        LEFT JOIN [Gold].[Dim_Tenants]    dt ON dt.Tenant_ID       = il.Tenant_ID
        LEFT JOIN [Audit].[Tenants]       t  ON t.Tenant_ID        = il.Tenant_ID
        WHERE il.Affiliate_ID IS NOT NULL;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #month;
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
