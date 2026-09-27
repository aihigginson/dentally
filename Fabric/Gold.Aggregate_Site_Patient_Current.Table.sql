/****** Object:  Table [Gold].[Aggregate_Site_Patient_Current]    Script Date: 07/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Site_Patient_Current]
GO
CREATE TABLE [Gold].[Aggregate_Site_Patient_Current](
	[pk_Site_Patient_Current]  [bigint]       NOT NULL,
	[fk_Site]                  [bigint]        NULL,
	[fk_Patient]               [bigint]        NULL,
	[Tenant_ID]                [int]           NOT NULL,
	[Retained_Patients]        [bit]           NULL,
	[Active_Patients]          [bit]           NULL,
	[Recall_Due]               [bit]           NULL,
	[Recall_Sent]              [bit]           NULL,
	[Future_Appointment]       [bit]           NULL,
	-- ==> WHAT THE PATIENT IS WORTH, ON THE TABLE THAT ALREADY DESCRIBES THE PATIENT. <==
	-- These arrived in V187 as a separate Gold.Aggregate_Patient_Value, which was one row per
	-- patient with a site and a tenant on it -- the same grain, the same load category and the
	-- same consumers as this table. Two aggregates describing the current state of one patient
	-- is how they drift: a column gets added to one, or a partial load leaves them disagreeing,
	-- and nothing says which is right. Folded in here before anything started reading the
	-- second one.
	--
	-- Rolling 36 months, and BOTH revenue types. The measure this replaces was
	-- SUM('List Patients'[Total Invoiced]) -- a membership patient's monthly fee is not an
	-- invoice, so on the live practice a plan patient showed as worth 737 against a private
	-- patient's 1,390 when the true figures are 2,876 and 1,414. It ranked the two largest
	-- cohorts the wrong way round, and it is the sort order of the dormant-patient worklist.
	--
	-- NOTE THE GRAIN. This table is named site x patient and is today one row per patient
	-- because a patient holds one Site_ID. Value is a PATIENT-level figure: if the grain ever
	-- widens to genuinely multiple sites per patient, summing these columns would double-count
	-- and they must move rather than be aggregated.
	[Value_Window_Months]      [smallint]      NULL,
	[Value_Window_From]        [date]          NULL,
	[Value_Invoiced]           [decimal](18,4) NULL,
	[Value_Capitation]         [decimal](18,4) NULL,   -- the half "lifetime value" omitted
	[Value_Total]              [decimal](18,4) NULL,
	[Appointments_Attended]    [int]           NULL,   -- engagement, not worth
	[Last_Attended_Date]       [date]          NULL,
	[Value_Per_Year]           [decimal](18,4) NULL,
	[DW_Created_At]            [datetime2](6)  NOT NULL,
	[DW_Updated_At]            [datetime2](6)  NOT NULL
)
GO
