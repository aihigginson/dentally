/****** Object:  Table [Gold].[Aggregate_Site_Practitioner_Current]    Script Date: 07/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Site_Practitioner_Current]
GO
CREATE TABLE [Gold].[Aggregate_Site_Practitioner_Current](
	[pk_Site_Practitioner_Current]    [bigint]       NOT NULL,
	[fk_Site]                         [bigint]        NULL,
	[fk_Practitioner]                 [bigint]        NULL,
	[Tenant_ID]                       [int]           NOT NULL,
	[Days_Until_Next_30_Mins]         [int]           NULL,
	[Days_Until_Next_1_Hour_Free]     [int]           NULL,
	[Next_7_Days_Available_Mins]      [int]           NULL,
	[Next_7_Days_Booked_Mins]         [int]           NULL,
	-- Day Book action counts held as TEXT so they can sit in the diary matrix ROW area
	-- (Stepped Layout = Off) and scroll WITH the heatmap. Split by site (fk_Site).
	[Open_Plans]                      [varchar](10)   NULL,  -- Course_Status IN (In Progress, Open - No Appointment)
	[Cancellations_To_Rebook]         [varchar](10)   NULL,  -- Is_Cancelled + Rebooked_Status = Not Rebooked
	[DNAs_To_Rebook]                  [varchar](10)   NULL,  -- Is_DNA + Rebooked_Status = Not Rebooked
	[Recalls_To_Action]               [varchar](10)   NULL,  -- Retention_Outlook_In_Scope=1 + Is_Booked=0
	[Days_Until_Next_30_Free]         [varchar](10)   NULL,  -- text mirror of Days_Until_Next_30_Mins (home-site row only)
	[DW_Created_At]                   [datetime2](6)  NOT NULL,
	[DW_Updated_At]                   [datetime2](6)  NOT NULL
)
GO
