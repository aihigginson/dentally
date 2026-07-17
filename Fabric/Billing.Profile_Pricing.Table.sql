-- Billing schema for subscription invoicing.
IF SCHEMA_ID('Billing') IS NULL EXEC('CREATE SCHEMA Billing');
GO
-- Billing.Profile_Pricing
-- Vendor pricing per profile, EFFECTIVE FROM a month (Year_Month = YYYYMM). Reprice by INSERTing a
-- new (Profile_Key, Year_Month) row in SQL -- no app change. The invoice rollup uses the latest row
-- with Year_Month <= the billed month. IDEMPOTENT CREATE so pricing survives redeploys.
IF OBJECT_ID('Billing.Profile_Pricing') IS NULL
CREATE TABLE [Billing].[Profile_Pricing] (
    [Profile_Key]   [varchar](50)  NOT NULL,   -- 'full' | 'clinician' | 'front_office'
    [Year_Month]    [int]          NOT NULL,    -- YYYYMM, e.g. 202701 = effective from Jan 2027
    [Monthly_Price] [decimal](9,2) NOT NULL
);
GO
