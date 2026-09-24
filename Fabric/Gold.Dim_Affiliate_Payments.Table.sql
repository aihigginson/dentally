/****** Object:  Table [Gold].[Dim_Affiliate_Payments]    Script Date: 24/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Dim_Affiliate_Payments
--  Notes  :  What we have ACTUALLY PAID an affiliate, from Billing.Affiliate_Payout. Without it
--            nothing records settlement and every commission reads as forever owing.
--            Year_Month is the statement month the payment SETTLES, not when it was sent:
--            August commission paid in October is 202608, or the statement never balances.
--            Dim pattern: MERGE upsert on the payout id.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Affiliate_Payments]
GO
CREATE TABLE [Gold].[Dim_Affiliate_Payments](
    [pk_Affiliate_Payment] [bigint]        NOT NULL,
    [bk_Payout_ID]         [int]           NOT NULL,
    [fk_Affiliate]         [bigint]            NULL,
    [fk_Date_Paid]         [int]               NULL,
    [Affiliate_Email]      [varchar](255)      NULL,
    [Affiliate_Name]       [varchar](255)      NULL,
    [Year_Month]           [int]           NOT NULL,
    [Month_Start]          [date]              NULL,
    [Amount_Paid]          [decimal](10,2) NOT NULL,
    [Paid_Date]            [date]          NOT NULL,
    [Reference]            [varchar](100)      NULL,
    [Notes]                [varchar](255)      NULL,
    [Payment_Count]        [int]               NULL,
    [DW_Created_At]        [datetime2](6)  NOT NULL,
    [DW_Updated_At]        [datetime2](6)  NOT NULL
)
GO
