/****** Object:  Table [Gold].[Fact_Contracts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Contracts]
GO
CREATE TABLE [Gold].[Fact_Contracts](
	[pk_Contract] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Contract_ID] [VARCHAR](50) NOT NULL,
	[fk_Practice_Site] [bigint] NULL,
	[fk_Date_Start] [bigint] NULL,
	[fk_Date_End] [bigint] NULL,
	[Contract_Number] [int] NULL,
	[NHS_Location_ID] [int] NULL,
	[NHS_Site_ID] [int] NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Active] [bit] NULL,
	[PDS_Plus] [bit] NULL,
	[Start_Date] [date] NULL,
	[End_Date] [date] NULL,
	[UDA_Target] [decimal](18, 4) NULL,
	[UDA_Value] [decimal](18, 4) NULL,
	[UOA_Target] [decimal](18, 4) NULL,
	[UOA_Value] [decimal](18, 4) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO

