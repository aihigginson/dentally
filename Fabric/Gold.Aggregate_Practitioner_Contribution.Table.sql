/****** Object:  Table [Gold].[Aggregate_Practitioner_Contribution]  ******/
-- Practitioner contribution: gross production and the associate-pay split, per
-- Practitioner x Site x Invoice-date. Contribution = Production - Associate_Pay
-- (what the practice retains from that practitioner). Associate_Pct comes from the
-- admin-entered Input.Practitioner_Pay; a practitioner with no % (e.g. a principal)
-- has pay 0 and keeps full production. Rebuilt each run.
-- CAVEAT: Production = SUM(Fact_Invoice_Items.Total_Price) (gross invoiced). NHS/UDA
-- income isn't invoice-priced, so NHS-heavy practitioners understate here for now.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Practitioner_Contribution]
GO
CREATE TABLE [Gold].[Aggregate_Practitioner_Contribution](
	[pk_Practitioner_Contribution] [bigint]        NOT NULL,
	[Tenant_ID]                    [int]           NOT NULL,
	[fk_Practitioner]              [bigint]        NULL,
	[fk_Practice_Site]             [bigint]        NULL,
	[fk_Date]                      [bigint]        NULL,
	[Production]                   [decimal](18,2) NULL,
	[Associate_Pct]                [decimal](6,3)  NULL,
	[Associate_Pay]                [decimal](18,2) NULL,
	[Contribution]                 [decimal](18,2) NULL,
	[DW_Created_At]                [datetime2](6)  NOT NULL,
	[DW_Updated_At]                [datetime2](6)  NOT NULL
)
GO
