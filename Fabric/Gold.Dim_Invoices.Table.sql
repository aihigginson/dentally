/****** Object:  Table [Gold].[Dim_Invoices]    Script Date: 20/06/2026 ******/
-- Invoice header dimension (1 row per invoice). Holds invoice ATTRIBUTES only.
-- The additive invoice amounts live in Gold.Fact_Invoices and the line amounts in
-- Gold.Fact_Invoice_Items; both facts relate to this dim via fk_Invoice. This split
-- replaces the previous design where invoice header amounts were folded onto every
-- invoice line (causing double-counting when summed).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Invoices]
GO
CREATE TABLE [Gold].[Dim_Invoices](
    [pk_Invoice]         [bigint]        NOT NULL,
    [Tenant_ID]          [int]           NOT NULL,
    [bk_Invoice_ID]      [int]           NOT NULL,
    [Invoice_Reference]  [varchar](50)   NULL,
    [Payment_Terms]      [varchar](255)  NULL,
    [Footnote]           [varchar](255)  NULL,
    [Invoice_Paid]       [bit]           NULL,
    [Status]             [varchar](50)   NULL,
    [Invoice_Dated_On]   [date]          NULL,
    [DW_Created_At]      [datetime2](6)  NOT NULL,
    [DW_Updated_At]      [datetime2](6)  NOT NULL
)
GO
