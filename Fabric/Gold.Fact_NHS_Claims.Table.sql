/****** Object:  Table [Gold].[Fact_NHS_Claims]    Script Date: 03/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_NHS_Claims]
GO
CREATE TABLE [Gold].[Fact_NHS_Claims](
	[pk_NHS_Claim] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_NHS_Claim_ID] [VARCHAR](50) NOT NULL,

	[fk_Patient] [bigint] NULL,
	[fk_Practitioner] [bigint] NULL,
	[fk_Treatment_Plan] [bigint] NULL,
	[fk_Practice_Site] [bigint] NULL,
	[fk_NHS_Contract] [bigint] NULL,

	[fk_Date_Submitted] [bigint] NULL,
	[fk_Date_Approval] [bigint] NULL,

	[Claim_Status] [VARCHAR](50) NULL,
	[Sequence_Number] [int] NULL,
	[UDA_Band] [VARCHAR](10) NULL,
	[Ortho] [bit] NULL,
	[Continuation_Part_Number] [int] NULL,
	[Status_Comments] [VARCHAR](max) NULL,

	[Expected_UDA] [decimal](18, 4) NULL,
	[Awarded_UDA] [decimal](18, 4) NULL,
	[Patient_Charge] [decimal](18, 4) NULL,
	[Dentist_Charge] [decimal](18, 4) NULL,
	[Awarded_Dentist_Charge] [decimal](18, 4) NULL,
	[NI_Calculated_Dentist_Fee] [decimal](18, 4) NULL,
	[NI_Calculated_Patient_Fee] [decimal](18, 4) NULL,
	[SCOT_Amount_Authorised] [decimal](18, 4) NULL,
	[SCOT_Amount_Expected] [decimal](18, 4) NULL,

	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
