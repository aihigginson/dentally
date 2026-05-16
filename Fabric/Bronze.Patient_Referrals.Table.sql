/****** Object:  Table [Bronze].[Patient_Referrals]    Script Date: 15/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Patient_Referrals]
GO
CREATE TABLE [Bronze].[Patient_Referrals](
	[Tenant_ID]                [int]            NOT NULL,
	[ID]                       [int]            NOT NULL,
	[Patient_ID]               [decimal](18, 4) NULL,
	[Site_ID]                  [varchar](255)   NULL,
	[User_ID]                  [decimal](18, 4) NULL,
	[Reference]                [varchar](255)   NULL,
	[Status]                   [varchar](255)   NULL,
	[Referrable_Type]          [varchar](255)   NULL,
	[Services_Appointment_ID]  [varchar](255)   NULL,
	[Additional_Information]   [varchar](max)   NULL,
	[Consented_By_Patient]     [varchar](10)    NULL,
	[Referred_Practitioner_ID] [decimal](18, 4) NULL,
	[Referred_Site_ID]         [varchar](255)   NULL,
	[Created_At]               [varchar](255)   NULL,
	[Updated_At]               [varchar](255)   NULL,
	[DW_Loaded_At]             [datetime2](6)   NOT NULL
)
GO
