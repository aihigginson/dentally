/****** Object:  Table [Bronze].[NHS_Claims]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[NHS_Claims]
GO
CREATE TABLE [Bronze].[NHS_Claims](
	[ID] [VARCHAR](255) NULL,
	[Awarded_UDA] [decimal](18, 4) NULL,
	[Approval_Date] [VARCHAR](255) NULL,
	[Contract_ID] [VARCHAR](255) NULL,
	[Claim_Status] [VARCHAR](255) NULL,
	[Expected_UDA] [decimal](18, 4) NULL,
	[Patient_ID] [decimal](18, 4) NULL,
	[Practitioner_ID] [int] NULL,
	[Sequence_Number] [decimal](18, 4) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Status_Comments] [VARCHAR](255) NULL,
	[Treatment_Plan_ID] [decimal](18, 4) NULL,
	[Submitted_Date] [VARCHAR](255) NULL,
	[Patient_Charge] [decimal](18, 4) NULL,
	[Scot_Amount_Authorised] [decimal](18, 4) NULL,
	[Scot_Amount_Expected] [decimal](18, 4) NULL,
	[UDA_Band] [decimal](18, 4) NULL,
	[Ortho] [decimal](18, 4) NULL,
	[Continuation_Part_Number] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
