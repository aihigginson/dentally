/****** Object:  Table [Silver].[Treatment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Treatment_Plans]
GO
CREATE TABLE [Silver].[Treatment_Plans](
	[Id] [int] NOT NULL,
	[Nickname] [VARCHAR](50) NULL,
	[Patient_Id] [int] NULL,
	[Practitioner_Id] [int] NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[Completed] [int] NULL,
	[Nhs_Course_Part] [VARCHAR](50) NULL,
	[Accepted_At] [VARCHAR](50) NULL,
	[Completed_At] [VARCHAR](50) NULL,
	[Last_Completed_At] [VARCHAR](50) NULL,
	[NHS_UDA_Value] [VARCHAR](50) NULL,
	[NHS_Completed_UDA_Value] [VARCHAR](50) NULL,
	[Private_treatment_value] [VARCHAR](50) NULL,
	[Start_Date] [VARCHAR](50) NULL,
	[End_Date] [VARCHAR](50) NULL,
	[Created_At] [VARCHAR](50) NULL,
	[Updated_At] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
