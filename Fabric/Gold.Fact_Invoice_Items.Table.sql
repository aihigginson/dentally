/****** Object:  Table [Gold].[Fact_Invoice_Items]    Script Date: 20/06/2026 ******/
-- Invoice-LINE grain fact (1 row per invoice line). Holds line amounts only. The
-- invoice header amounts (Invoice_Amount/Outstanding/NHS, Is_Invoice_Outstanding) and
-- attributes (Reference/Payment_Terms/Footnote/Paid) were previously folded onto every
-- line here (double-counting risk) and now live on Gold.Fact_Invoices /
-- Gold.Dim_Invoices respectively. fk_Invoice relates each line to its invoice.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Invoice_Items]
GO
CREATE TABLE [Gold].[Fact_Invoice_Items](
    [pk_Invoice_Item]        [bigint] IDENTITY NOT NULL,
    [Tenant_ID]              [int]            NOT NULL,
    [bk_Invoice_Item_ID]     [VARCHAR](255)   NOT NULL,
    [fk_Invoice]             [bigint]         NULL,
    [fk_Patient]             [bigint]         NULL,
    [fk_Practitioner]        [bigint]         NULL,
    [fk_Payment_Plan]        [bigint]         NULL,
    [fk_Treatment_Plan]      [bigint]         NULL,
    [fk_Account]             [bigint]         NULL,
    [fk_Practice_Site]       [bigint]         NULL,
    [fk_User]                [bigint]         NULL,
    [fk_Date_Invoice]        [bigint]         NULL,
    [fk_Date_Created]        [bigint]         NULL,
    [Invoice_ID]             [bigint]         NULL,
    [Treatment_Plan_Item_ID] [bigint]         NULL,
    [Sundry_ID]              [VARCHAR](255)   NULL,
    [Item_Name]              [VARCHAR](255)   NULL,
    [Item_Price]             [decimal](12, 2) NULL,
    [Quantity]               [decimal](10, 4) NULL,
    [Total_Price]            [decimal](12, 2) NULL,
    [NHS_Charge]             [decimal](12, 2) NULL,
    [DW_Created_At]          [datetime2](6)   NOT NULL,
    [DW_Updated_At]          [datetime2](6)   NOT NULL
)
GO
