/****** Object:  Table [Gold].[Aggregate_Site_Practitioner_Current]    Script Date: 07/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Site_Practitioner_Current]
GO
CREATE TABLE [Gold].[Aggregate_Site_Practitioner_Current](
	[pk_Site_Practitioner_Current]    [bigint]       NOT NULL,
	[fk_Site]                         [bigint]        NULL,
	[fk_Practitioner]                 [bigint]        NULL,
	[Tenant_ID]                       [int]           NOT NULL,
	[Days_Until_Next_30_Mins]         [int]           NULL,
	[Days_Until_Next_1_Hour_Free]     [int]           NULL,
	[DW_Created_At]                   [datetime2](6)  NOT NULL,
	[DW_Updated_At]                   [datetime2](6)  NOT NULL
)
GO
