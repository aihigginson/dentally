/****** Object:  Table [Gold].[Aggregate_Site_Patient_Practitioner_Daily]    Script Date: 07/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Site_Patient_Practitioner_Daily]
GO
CREATE TABLE [Gold].[Aggregate_Site_Patient_Practitioner_Daily](
	[pk_Site_Patient_Practitioner_Daily]  [bigint]        NOT NULL,
	[fk_Site]                             [bigint]        NULL,
	[fk_Patient]                          [bigint]        NULL,
	[fk_Practitioner]                     [bigint]        NULL,
	[fk_Date]                             [bigint]        NULL,
	[Tenant_ID]                           [int]           NOT NULL,
	[NHS_UDAs]                            [decimal](10,2) NULL,
	[NHS_UOAs]                            [decimal](10,2) NULL,
	[Appointments]                        [int]           NULL,
	[DNA_Appointments]                    [int]           NULL,
	[BBYL_Appointments]                   [int]           NULL,
	[NHS_Revenue]                         [decimal](12,2) NULL,
	[Private_Revenue]                     [decimal](12,2) NULL,
	[Open_Treatment_Plan]                 [int]           NULL,
	[Future_Appointment]                  [bit]           NULL,
	[Exam_Count]                          [int]           NULL,
	[Treatment_Count]                     [int]           NULL,
	[New_Patient]                         [bit]           NULL,
	[Worked_Hours]                        [decimal](10,2) NULL,
	[Appointment_Hours]                   [decimal](10,2) NULL,
	[Cancelled_Appointments]              [int]           NULL,
	[Short_Notice_Cancellations]          [int]           NULL,
	[DW_Created_At]                       [datetime2](6)  NOT NULL,
	[DW_Updated_At]                       [datetime2](6)  NOT NULL
)
GO
