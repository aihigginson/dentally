/****** Object:  Table [Gold].[Fact_NHS_Contract_Week]    Script Date: 12/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_NHS_Contract_Week]
GO
CREATE TABLE [Gold].[Fact_NHS_Contract_Week](
	[pk_NHS_Contract_Week]       [bigint]        NOT NULL,
	[fk_NHS_Contract]            [bigint]        NOT NULL,
	[fk_Date_Week_Start]         [int]           NOT NULL,
	[Tenant_ID]                  [int]           NOT NULL,
	[Financial_Year]             [smallint]      NOT NULL,
	[Financial_Week]             [smallint]      NOT NULL,
	[Working_Days_In_Week]       [smallint]      NOT NULL,
	[Total_Working_Days_In_Year] [smallint]      NOT NULL,
	[Pro_Rata_UDA_Target]        [decimal](18,4) NOT NULL,
	[DW_Created_At]              [datetime2](3)  NOT NULL
)
GO
