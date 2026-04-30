/****** Object:  Table [Silver].[Patient_Referral_Reasons]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Patient_Referral_Reasons]
GO
CREATE TABLE [Silver].[Patient_Referral_Reasons](
	[Tenant_ID] [int] NOT NULL,
	[Patient_Referral_Id] [int] NOT NULL,
	[Referral_Reason_Id] [VARCHAR](50) NOT NULL,
	[Name] [VARCHAR](255) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
