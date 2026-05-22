/****** Object:  Table [Silver].[NHS_Claims]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[NHS_Claims]
GO
CREATE TABLE [Silver].[NHS_Claims](
	[Tenant_ID] [int] NOT NULL,
	[NHS_Claim_ID] [VARCHAR](50) NOT NULL,
	[Patient_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Treatment_Plan_ID] [int] NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Contract_ID] [VARCHAR](50) NULL,
	[Claim_Status] [VARCHAR](50) NULL,
	[Sequence_Number] [int] NULL,
	[UDA_Band] [VARCHAR](10) NULL,
	[Expected_UDA] [decimal](18, 4) NULL,
	[Awarded_UDA] [decimal](18, 4) NULL,
	[Patient_Charge] [decimal](18, 4) NULL,
	[Dentist_Charge] [decimal](18, 4) NULL,
	[Awarded_Dentist_Charge] [decimal](18, 4) NULL,
	[NI_Calculated_Dentist_Fee] [decimal](18, 4) NULL,
	[NI_Calculated_Patient_Fee] [decimal](18, 4) NULL,
	[SCOT_Amount_Authorised] [decimal](18, 4) NULL,
	[SCOT_Amount_Expected] [decimal](18, 4) NULL,
	[Ortho] [bit] NULL,
	[Continuation_Part_Number] [int] NULL,
	[Status_Comments] [VARCHAR](max) NULL,
	[Approval_Date] [date] NULL,
	[Submitted_Date] [date] NULL,
	[NHS_Updated_At] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
