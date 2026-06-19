/****** Object:  Table [Audit].[Rerun_Plan]    Script Date: 17/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Rerun_Plan]
GO
CREATE TABLE [Audit].[Rerun_Plan](
    [Rerun_ID]              [uniqueidentifier] NULL,
    [Exec_Seq]              [int]              NULL,
    [Process_Code]          [varchar](100)     NULL,
    [Process_Name]          [varchar](1000)    NULL,
    [Process_Category_Code] [varchar](100)     NULL,
    [Run_Level]             [int]              NULL,
    [Is_Downstream]         [int]              NULL,
    [Failed_Options]        [varchar](4000)    NULL,   -- resolved Process_Options of the failed run (carries @Tenant_ID for per-tenant Bronze reruns)
    [Planned_At]            [datetime2](3)     NULL
)
GO
