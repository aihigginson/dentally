/****** Object:  Table [Silver].[Practitioner_Contract_Targets]    Script Date: 12/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[Silver].[Practitioner_Contract_Targets]', 'U') IS NULL
CREATE TABLE [Silver].[Practitioner_Contract_Targets](
	[Tenant_ID]            [int]            NOT NULL,
	[bk_Practitioner_ID]   [int]            NOT NULL,
	[bk_Contract_ID]       [VARCHAR](50)    NOT NULL,
	[UDA_Target]           [decimal](18,4)  NULL,
	[UOA_Target]           [decimal](18,4)  NULL,
	[Is_Default]           [bit]            NULL,
	[DW_Created_At]        [datetime2](3)   NOT NULL,
	[DW_Updated_At]        [datetime2](3)   NOT NULL
)
GO
