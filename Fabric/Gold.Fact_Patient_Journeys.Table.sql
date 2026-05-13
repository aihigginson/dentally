/****** Object:  Table [Gold].[Fact_Patient_Journeys]    Script Date: 13/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Patient_Journeys]
GO
CREATE TABLE [Gold].[Fact_Patient_Journeys](
	[pk_patient_journey]  [int]           NOT NULL,
	[Channel]             [varchar](50)  NOT NULL,
	[Current_Appointment] [varchar](50)  NOT NULL,
	[Next_Outcome]        [varchar](100) NOT NULL,
	[Next_Appointment]    [varchar](50)  NOT NULL,
	[Current_State]       [varchar](50)  NOT NULL,
	[Patient_Count]       [int]           NOT NULL
)
GO
