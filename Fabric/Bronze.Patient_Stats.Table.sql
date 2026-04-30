/****** Object:  Table [Bronze].[Patient_Stats]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Patient_Stats]
GO
CREATE TABLE [Bronze].[Patient_Stats](
	[Last_Appointment_Date] [VARCHAR](255) NULL,
	[Last_Exam_Date] [VARCHAR](255) NULL,
	[Last_Scale_And_Polish_Date] [VARCHAR](255) NULL,
	[Next_Appointment_Date] [VARCHAR](255) NULL,
	[Next_Exam_Date] [VARCHAR](255) NULL,
	[Next_Scale_And_Polish_Date] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Total_Paid] [decimal](18, 4) NULL,
	[Total_Invoiced] [decimal](18, 4) NULL,
	[Last_Fta_Appointment_Date] [VARCHAR](255) NULL,
	[First_Appointment_Date] [VARCHAR](255) NULL,
	[First_Exam_Date] [VARCHAR](255) NULL,
	[NHS_Exemption_Code] [decimal](18, 4) NULL,
	[Patient_ID] [decimal](18, 4) NULL,
	[Last_Cancelled_Appointment_Date] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
