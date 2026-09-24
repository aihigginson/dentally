-- Billing.Affiliate_Payout
-- What we have ACTUALLY PAID an affiliate. Without it "outstanding" cannot be computed at all:
-- Billing.Invoice_Line records what was EARNED and nothing anywhere recorded what was settled,
-- so every commission would read as forever owing.
--
-- Grain: one row per payment. Year_Month is the statement month the payment SETTLES, not the
-- month it was sent -- commission for August paid in October is Year_Month 202608, or the
-- statement it clears would never balance.
--
-- Vendor-managed, like Billing.Affiliate: inserted by hand at payout time. IDEMPOTENT CREATE so
-- records survive redeploys -- this table holds payment history that cannot be regenerated from
-- anywhere else, and a DROP would lose it silently.
IF SCHEMA_ID('Billing') IS NULL EXEC('CREATE SCHEMA Billing');
GO
IF OBJECT_ID('Billing.Affiliate_Payout') IS NULL
CREATE TABLE [Billing].[Affiliate_Payout] (
    [Payout_ID]    [int]          NOT NULL,   -- surrogate, manually assigned (small set)
    [Affiliate_ID] [int]          NOT NULL,
    [Year_Month]   [int]          NOT NULL,   -- the statement month this settles, e.g. 202608
    [Amount]       [decimal](10,2) NOT NULL,  -- net, same basis as Invoice_Line.Value
    [Paid_At]      [date]         NOT NULL,
    [Reference]    [varchar](100)     NULL,   -- bank reference / their self-billing invoice no.
    [Notes]        [varchar](255)     NULL
);
GO
