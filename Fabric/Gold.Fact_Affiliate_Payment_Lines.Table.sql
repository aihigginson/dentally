/****** Object:  Table [Gold].[Fact_Affiliate_Payment_Lines]    Script Date: 24/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Fact_Affiliate_Payment_Lines
--  Notes  :  Grain  : AFFILIATE x PRACTICE x MONTH -- one line of what we owe a partner. NOT the
--                     subscription line. An affiliate is owed for introducing a practice, not for
--                     each user on it, so the individual billed users are summed into Billed_Users
--                     and are not a dimension of this fact.
--            Pattern: full rebuild (DELETE + INSERT), pk from ROW_NUMBER(), as
--                     Fact_Patient_At_Risk and Fact_Appointment_Journey already do. Wholly derived
--                     from Billing, so there is nothing an incremental load would protect.
--
--            THE GRAIN IS WHY THE ARITHMETIC IS EXACT. Credit notes are raised per practice-month,
--            which is precisely this grain -- so a credit attaches to the row it belongs to and is
--            rounded once. The earlier per-user grain had to apportion each credit pro rata across
--            a month's users, and the per-line roundings summed to six pence away from the figure
--            the month itself said. Nothing to reconcile now.
--
--            Commission_Accrued sums the values FROZEN ONTO Billing.Invoice_Line at generation
--            time rather than recalculating, so re-rating an affiliate cannot restate a statement
--            already settled.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Affiliate_Payment_Lines]
GO
CREATE TABLE [Gold].[Fact_Affiliate_Payment_Lines](
    [pk_Affiliate_Payment_Line] [bigint]       NOT NULL,
    [fk_Affiliate]        [bigint]            NULL,
    [fk_Tenant]           [bigint]            NULL,
    [fk_Date_Month]       [int]               NULL,
    [Tenant_ID]           [int]           NOT NULL,
    [Practice_Name]       [varchar](255)      NULL,
    [Affiliate_Email]     [varchar](255)      NULL,
    [Affiliate_Name]      [varchar](255)      NULL,
    [Year_Month]          [int]           NOT NULL,
    [Month_Start]         [date]              NULL,
    [Commission_Pct]      [decimal](6,3)      NULL,
    [Billed_Users]        [int]               NULL,   -- how many users made up the invoice
    [Invoiced_Net]        [decimal](10,2)     NULL,
    [Credited_Net]        [decimal](10,2)     NULL,
    [Net_After_Credits]   [decimal](10,2)     NULL,
    [Commission_Accrued]  [decimal](10,2)     NULL,   -- sum of the values frozen on the lines
    [Commission_On_Credits] [decimal](10,2)   NULL,   -- negative
    [Commission_Due]      [decimal](10,2)     NULL,
    [Customer_Invoice_Status] [varchar](30)   NULL,
    [Is_Customer_Paid]    [bit]               NULL,
    [Commission_Payable]  [decimal](10,2)     NULL,   -- 0 until the customer has actually paid
    [Line_Count]          [int]               NULL,
    [DW_Created_At]       [datetime2](6)  NOT NULL,
    [DW_Updated_At]       [datetime2](6)  NOT NULL
)
GO
