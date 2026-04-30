/****** Object:  Table [Silver].[Patient_Stats]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Patient_Stats]
GO
CREATE TABLE [Silver].[Patient_Stats](
	[Tenant_ID] [int] NOT NULL,
	[Patient_Id] [int] NOT NULL,
	[First_Appointment_Date] [VARCHAR](50) NULL,
	[First_Exam_Date] [VARCHAR](50) NULL,
	[Last_Appointment_Date] [VARCHAR](50) NULL,
	[Last_Exam_Date] [VARCHAR](50) NULL,
	[Last_Scale_And_Polish_Date] [VARCHAR](50) NULL,
	[Last_Fta_Appointment_Date] [VARCHAR](50) NULL,
	[Last_Cancelled_Appointment_Date] [VARCHAR](50) NULL,
	[Next_Appointment_Date] [VARCHAR](50) NULL,
	[Next_Exam_Date] [VARCHAR](50) NULL,
	[Next_Scale_And_Polish_Date] [VARCHAR](50) NULL,
	[Total_Paid] [decimal](18, 4) NULL,
	[Total_Invoiced] [decimal](18, 4) NULL,
	[Nhs_Exemption_Code] [VARCHAR](20) NULL,
	[Created_At] [VARCHAR](50) NULL,
	[Updated_At] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
