-- Billing.vw_Affiliate_Commission
-- The affiliate commission statement: one row per affiliate x practice x month. Both the
-- position (what is owed) and the thing you can filter to one affiliate and send.
--
-- ==> NOT IN THE CUSTOMER SEMANTIC MODEL. <== This is VENDOR money -- what we pay a referral
-- partner. 'PBI Dentally' is RLS-scoped per tenant and read by practice owners; a practice must
-- never see what an introducer earns from them, and the affiliate must never see other
-- practices. It belongs in its own small model over these views, shared with nobody.
--
-- THREE THINGS THIS GETS RIGHT THAT A NAIVE SUM(Affiliate_Commission_Value) DOES NOT:
--
-- 1. CREDIT NOTES ARE GROSS, INVOICE LINES ARE NET. Billing.Credit_Note.Amount_Pence INCLUDES
--    VAT (dev: £416.80 with £69.47 tax) while Billing.Invoice_Line.Value EXCLUDES it (£386.80).
--    Clawing back commission on the gross figure would overstate it by the VAT rate -- 20% too
--    much taken off the affiliate, every time. Net is Amount_Pence - Tax_Pence.
--    (Billing.Stripe_Invoice.Amount_Pence is NET, unlike Credit_Note. The two disagree; that is
--    existing schema, not a choice made here, and it is why neither is used as the invoiced
--    figure -- Invoice_Line is.)
--
-- 2. COMMISSION IS EARNED ON INVOICING BUT PAYABLE ON COLLECTION. Commission_Accrued is what the
--    invoice generated; Commission_Payable is 0 until Stripe says the customer actually paid.
--    Paying out on an uncollected invoice means funding a partner from our own pocket and then
--    trying to claw it back.
--
-- 3. THE RATE IS READ FROM THE LINE, NOT THE AFFILIATE. Invoice_Line.Affiliate_Commission_Pct is
--    frozen at generation time, so a rate change does not silently rewrite history. Joining
--    Billing.Affiliate for the rate instead would restate every past statement.
--
-- Affiliate name/email ARE joined live from Billing.Affiliate: those are contact details, where
-- current is what you want, not what was true in August.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [Billing].[vw_Affiliate_Commission]
GO
CREATE VIEW [Billing].[vw_Affiliate_Commission] AS
WITH lines AS (
    SELECT il.Affiliate_ID,
           il.Tenant_ID,
           il.Year_Month,
           MAX(il.Affiliate_Commission_Pct)        AS Commission_Pct,
           SUM(il.Value)                           AS Invoiced_Net,
           SUM(il.Affiliate_Commission_Value)      AS Commission_Accrued,
           COUNT(*)                                AS Billed_Users
    FROM [Billing].[Invoice_Line] il
    WHERE il.Affiliate_ID IS NOT NULL
    GROUP BY il.Affiliate_ID, il.Tenant_ID, il.Year_Month
),
credits AS (
    -- NET, not gross. See note 1 above.
    SELECT cn.Tenant_ID,
           cn.Year_Month,
           SUM(cn.Amount_Pence - ISNULL(cn.Tax_Pence, 0)) / 100.0 AS Credited_Net
    FROM [Billing].[Credit_Note] cn
    GROUP BY cn.Tenant_ID, cn.Year_Month
),
invoiced AS (
    -- One Stripe invoice per tenant-month in practice; MAX guards against a re-issue leaving two.
    SELECT si.Tenant_ID,
           si.Year_Month,
           MAX(si.Status) AS Customer_Invoice_Status
    FROM [Billing].[Stripe_Invoice] si
    GROUP BY si.Tenant_ID, si.Year_Month
)
SELECT
      l.Affiliate_ID
    , af.Name                                       AS Affiliate_Name
    , af.Email                                      AS Affiliate_Email
    , l.Tenant_ID
    , t.Tenant_Name                                 AS Practice_Name
    , l.Year_Month
    -- A real date as well as the YYYYMM integer: a PBI model cannot do anything useful with
    -- 202609 on an axis, and every month bucket in the report hangs off this.
    , DATEFROMPARTS(l.Year_Month / 100, l.Year_Month % 100, 1) AS Month_Start
    , l.Commission_Pct
    , l.Billed_Users
    , l.Invoiced_Net
    , ISNULL(c.Credited_Net, 0)                     AS Credited_Net
    , l.Invoiced_Net - ISNULL(c.Credited_Net, 0)    AS Net_After_Credits
    , l.Commission_Accrued
    -- Negative: what the credit takes back off the affiliate, at the rate frozen on the line.
    , CAST(ROUND(-ISNULL(c.Credited_Net, 0) * ISNULL(l.Commission_Pct, 0), 2) AS DECIMAL(10,2))
                                                    AS Commission_On_Credits
    , CAST(ROUND(l.Commission_Accrued
                 - ISNULL(c.Credited_Net, 0) * ISNULL(l.Commission_Pct, 0), 2) AS DECIMAL(10,2))
                                                    AS Commission_Due
    , ISNULL(i.Customer_Invoice_Status, 'not raised') AS Customer_Invoice_Status
    , CAST(CASE WHEN i.Customer_Invoice_Status = 'paid' THEN 1 ELSE 0 END AS BIT)
                                                    AS Is_Customer_Paid
    -- See note 2: earned on invoicing, payable only once collected.
    , CAST(CASE WHEN i.Customer_Invoice_Status = 'paid'
                THEN ROUND(l.Commission_Accrued
                           - ISNULL(c.Credited_Net, 0) * ISNULL(l.Commission_Pct, 0), 2)
                ELSE 0 END AS DECIMAL(10,2))        AS Commission_Payable
FROM lines l
LEFT JOIN [Billing].[Affiliate] af ON af.Affiliate_ID = l.Affiliate_ID
LEFT JOIN [Audit].[Tenants]     t  ON t.Tenant_ID     = l.Tenant_ID
LEFT JOIN credits   c ON c.Tenant_ID = l.Tenant_ID AND c.Year_Month = l.Year_Month
LEFT JOIN invoiced  i ON i.Tenant_ID = l.Tenant_ID AND i.Year_Month = l.Year_Month
GO

-- Billing.vw_Affiliate_Payout
-- What has actually been sent, at the same affiliate x month grain as the statement so the two
-- subtract cleanly. Kept as a separate view rather than joined into the statement because a
-- payout can exist for a month with no commission (a correction, a rounding settlement) and an
-- inner join would hide exactly the row someone is looking for.
DROP VIEW IF EXISTS [Billing].[vw_Affiliate_Payout]
GO
CREATE VIEW [Billing].[vw_Affiliate_Payout] AS
SELECT
      p.Affiliate_ID
    , af.Name  AS Affiliate_Name
    , af.Email AS Affiliate_Email
    , p.Year_Month
    , DATEFROMPARTS(p.Year_Month / 100, p.Year_Month % 100, 1) AS Month_Start
    , p.Payout_ID
    , p.Amount AS Amount_Paid
    , p.Paid_At
    , p.Reference
    , p.Notes
FROM [Billing].[Affiliate_Payout] p
LEFT JOIN [Billing].[Affiliate] af ON af.Affiliate_ID = p.Affiliate_ID
GO
