/****** Object:  Table [Silver].[Patient_Referrals]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Patient_Referrals]
GO
CREATE TABLE [Silver].[Patient_Referrals](
	[Tenant_ID] [int] NOT NULL,
	[Patient_Referral_ID] [int] NOT NULL,
	[Patient_ID] [int] NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[User_ID] [int] NULL,
	[Reference] [VARCHAR](50) NULL,
	[Status] [VARCHAR](50) NULL,
	[Referrable_Type] [VARCHAR](100) NULL,
	[Services_Appointment_ID] [VARCHAR](50) NULL,
	[Additional_Information] [VARCHAR](max) NULL,
	[Consented_By_Patient] [bit] NULL,
	[Referred_Practitioner_ID] [int] NULL,
	[Referred_Site_ID] [VARCHAR](50) NULL,
	[Created_At] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
