/****** Object:  Table [Gold].[Fact_Affiliate_Payment_Lines]    Script Date: 24/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Fact_Affiliate_Payment_Lines
--  Notes  :  Grain  : one row per BILLED USER per practice per month -- the invoice line the
--                     commission was earned on. Every figure in the statement rolls up from here.
--            Pattern: full rebuild (DELETE + INSERT), pk from ROW_NUMBER(), as
--                     Fact_Patient_At_Risk and Fact_Appointment_Journey already do. It is wholly
--                     derived from Billing, so there is nothing an incremental load would protect.
--
--            Commission_Value is the figure FROZEN ONTO Billing.Invoice_Line at generation time,
--            not a recalculation: changing an affiliate's rate must never restate a statement
--            already paid against.
--
--            Credited_Net is apportioned PRO RATA across the month's lines. Credit notes are
--            raised per practice-month, not per user, so there is no line to attach them to; the
--            alternative -- holding credits at a coarser grain -- means the fact does not add up
--            to the statement, which is worse.
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
    [User_UPN]            [varchar](255)      NULL,
    [Display_Name]        [varchar](255)      NULL,
    [Profile_Key]         [varchar](50)       NULL,
    [Commission_Pct]      [decimal](6,3)      NULL,
    [Invoiced_Net]        [decimal](10,2)     NULL,
    [Credited_Net]        [decimal](10,2)     NULL,   -- pro rata share of the month's credit
    [Net_After_Credits]   [decimal](10,2)     NULL,
    [Commission_Accrued]  [decimal](10,2)     NULL,   -- as frozen on the invoice line
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
