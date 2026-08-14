/****** Object:  Table [Gold].[Dim_NHS_Contracts]    Script Date: 03/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_NHS_Contracts]
GO
CREATE TABLE [Gold].[Dim_NHS_Contracts](
	[pk_NHS_Contract] [bigint] NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Contract_ID] [VARCHAR](50) NOT NULL,
	[Contract_Number] [VARCHAR](50) NULL,
	[Contract_Name] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Active] [bit] NULL,
	[PDS_Plus] [bit] NULL,
	[NHS_Location_ID] [VARCHAR](50) NULL,
	[NHS_Site_ID] [VARCHAR](50) NULL,
	[Start_Date] [date] NULL,
	[End_Date] [date] NULL,
	[UDA_Target] [decimal](18, 4) NULL,
	[UDA_Value] [decimal](18, 4) NULL,
	[UOA_Target] [decimal](18, 4) NULL,
	[UOA_Value] [decimal](18, 4) NULL,
	[Is_Rolled_Forward] [bit] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
