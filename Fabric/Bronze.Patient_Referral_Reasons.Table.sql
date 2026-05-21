/****** Object:  Table [Bronze].[Patient_Referral_Reasons]    Script Date: 19/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Patient_Referral_Reasons]
GO
CREATE TABLE [Bronze].[Patient_Referral_Reasons](
	[Patient_Referral_ID] [decimal](18, 4) NULL,
	[Referral_Reason_ID] [VARCHAR](255) NULL,
	[Name] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
