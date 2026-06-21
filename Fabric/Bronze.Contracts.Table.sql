/****** Object:  Table [Bronze].[Contracts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Contracts]
GO
CREATE TABLE [Bronze].[Contracts](
	[ID] [VARCHAR](255) NULL,
	[Active] [VARCHAR](255) NULL,
	[Contract_Number] [VARCHAR](255) NULL,
	[End_Date] [VARCHAR](255) NULL,
	[NHS_Location_ID] [VARCHAR](255) NULL,
	[NHS_Site_ID] [VARCHAR](255) NULL,
	[PDS_Plus] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Start_Date] [VARCHAR](255) NULL,
	[Target] [VARCHAR](255) NULL,
	[UDA_Value] [VARCHAR](255) NULL,
	[UOA_Target] [VARCHAR](255) NULL,
	[UOA_Value] [VARCHAR](255) NULL,
	[Name] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
