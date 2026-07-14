/****** Object:  Table [Gold].[Fact_Patient_At_Risk] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Patient_At_Risk]
GO
-- "At Risk" patients: ACTIVE patients (Active=1 AND seen within 730 days) with no relevant future
-- appointment, who have fallen through a retention route. One row per (patient x route); a patient
-- loose on several routes gets several rows. Routes (Risk_Route), all filterable in the report:
--   'Recall - Dentist'            due <=4wk, no future exam       (Risk_Detail = Recall Active / No Recall)
--   'Recall - Hygiene'            due <=4wk, no future scale&polish (Risk_Detail = Recall Active / No Recall)
--   'Cancelled Not Rebooked'      cancelled <=90d ago, no future appointment (reason unavailable on
--                                 real Dentally data, so no reason-based exclusion -- Active flag guards)
--   'Open Treatment No Appt'      open (started, incomplete) course, no future appointment
CREATE TABLE [Gold].[Fact_Patient_At_Risk](
	[pk_At_Risk]          [bigint]        NOT NULL,
	[Tenant_ID]           [int]           NOT NULL,
	[fk_Patient]          [bigint]        NULL,
	[fk_Practice_Site]    [bigint]        NULL,
	[fk_Practitioner]     [bigint]        NULL,
	[Risk_Route]          [varchar](40)   NULL,
	[Risk_Detail]         [varchar](40)   NULL,
	[Reference_Date]      [date]          NULL,
	[Has_Live_Recall]     [bit]           NULL,
	[DW_Created_At]       [datetime2](6)  NOT NULL,
	[DW_Updated_At]       [datetime2](6)  NOT NULL
)
GO
