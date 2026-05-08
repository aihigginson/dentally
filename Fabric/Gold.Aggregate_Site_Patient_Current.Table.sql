/****** Object:  Table [Gold].[Aggregate_Site_Patient_Current]    Script Date: 07/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Site_Patient_Current]
GO
CREATE TABLE [Gold].[Aggregate_Site_Patient_Current](
	[pk_Site_Patient_Current]  [bigint]       NOT NULL,
	[fk_Site]                  [bigint]        NULL,
	[fk_Patient]               [bigint]        NULL,
	[Tenant_ID]                [int]           NOT NULL,
	[Retained_Patients]        [bit]           NULL,
	[Active_Patients]          [bit]           NULL,
	[Recall_Due]               [bit]           NULL,
	[Recall_Sent]              [bit]           NULL,
	[Future_Appointment]       [bit]           NULL,
	[DW_Created_At]            [datetime2](6)  NOT NULL,
	[DW_Updated_At]            [datetime2](6)  NOT NULL
)
GO
