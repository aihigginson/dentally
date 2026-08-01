/****** Object:  Table [Gold].[Fact_Lapsed_Patients]    Script Date: 08/01/2026 ******/
-- One row per lapsed patient (Dim_Patients.Lapsed_Type IS NOT NULL), dated by the lapse date so a
-- patient-level lapsed report slices natively by Period / Site / Practitioner -- the star-schema fix
-- for date-slicing a dimension event (a Dim behaving like a fact was the root cause fixed once before
-- by Fact_Treatment_Plans, V019). Aggregate lapsed counts already live in Fact_Metric_Actuals; THIS
-- fact exists for the patient LIST + reason breakdown (deactivated vs long-silent).
-- Built full-rebuild (DROP/CREATE) by Gold.usp_Load_Fact_Lapsed_Patients. GOLD_AGG (reads Dim_Patients).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Lapsed_Patients]
GO
CREATE TABLE [Gold].[Fact_Lapsed_Patients] (
    [pk_Lapsed_Patient]       BIGINT IDENTITY NOT NULL,
    [Tenant_ID]               INT             NOT NULL,
    [bk_Patient_ID]           INT             NOT NULL,
    [fk_Patient]              BIGINT          NOT NULL,
    [fk_Practitioner]         BIGINT          NOT NULL,
    [fk_Practice_Site]        BIGINT          NOT NULL,
    [fk_Payment_Plan]         BIGINT          NOT NULL,
    [fk_Date_Lapsed]          BIGINT          NOT NULL,
    [Lapsed_Type]             VARCHAR(30)     NULL,
    [Lapsed_Reason]           VARCHAR(255)    NULL,
    [Lapsed_Date]             DATE            NULL,
    [Lapsed_Patient_Count]    INT             NOT NULL,
    [DW_Created_At]           DATETIME2(3)    NOT NULL
)
GO
