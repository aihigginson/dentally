/****** Object:  Table [Gold].[Fact_Invoices]    Script Date: 20/06/2026 ******/
-- Invoice-grain fact (1 row per invoice). Holds the additive invoice amounts that
-- were previously folded onto every invoice line in Fact_Invoice_Items (which caused
-- double-counting when summed). Relates to Gold.Dim_Invoices via fk_Invoice and to the
-- shared dims (Patient/Account/Practice_Site/User/Date). Header ATTRIBUTES live on
-- Gold.Dim_Invoices; line amounts live on Gold.Fact_Invoice_Items.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Invoices]
GO
CREATE TABLE [Gold].[Fact_Invoices](
    [pk_Fact_Invoice]             [bigint] IDENTITY NOT NULL,
    [Tenant_ID]                   [int]            NOT NULL,
    [bk_Invoice_ID]               [int]            NOT NULL,
    [fk_Invoice]                  [bigint]         NULL,
    [fk_Patient]                  [bigint]         NULL,
    [fk_Account]                  [bigint]         NULL,
    [fk_Practice_Site]            [bigint]         NULL,
    [fk_User]                     [bigint]         NULL,
    [fk_Date_Invoice]             [bigint]         NULL,
    [fk_Date_Due]                 [bigint]         NULL,
    [fk_Date_Paid]                [bigint]         NULL,
    [Invoice_Amount]              [decimal](12, 2) NULL,
    [Invoice_Amount_Outstanding]  [decimal](12, 2) NULL,
    [Invoice_NHS_Amount]          [decimal](12, 2) NULL,
    [Is_Invoice_Outstanding]      [bit]            NULL,
    [DW_Created_At]               [datetime2](6)   NOT NULL,
    [DW_Updated_At]               [datetime2](6)   NOT NULL
)
GO
