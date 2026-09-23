/****** Object:  Table [Gold].[Aggregate_Data_Quality]    Script Date: 22/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Aggregate_Data_Quality
--  Author :  AIH
--  Notes  :  Grain   : Tenant x Check. One row per check per practice, ALWAYS --
--                      including the checks that pass, which is the point: a
--                      scorecard that only listed problems could not be told apart
--                      from a scorecard that failed to run.
--            Pattern : Aggregate -- full DELETE + INSERT each run, pk from ROW_NUMBER().
--
--            The catalogue columns (Check_Name, Severity, Why_It_Matters, What_To_Do)
--            are DENORMALISED from Config.Data_Quality_Check so Power BI imports one
--            flat table and needs no relationship beyond RLS on Tenant_ID.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Data_Quality]
GO
CREATE TABLE [Gold].[Aggregate_Data_Quality] (
    [pk_Data_Quality]   [bigint]        NOT NULL,
    [Tenant_ID]         [int]           NOT NULL,
    [Tenant_Check_Key]  [varchar](80)   NOT NULL,   -- 1:many join to Fact_Data_Quality_Detail
    [Check_Code]        [varchar](50)   NOT NULL,
    [Check_Category]    [varchar](30)   NOT NULL,
    [Check_Name]        [varchar](200)  NOT NULL,
    [Severity]          [varchar](10)   NOT NULL,
    [Severity_Sort]     [smallint]      NOT NULL,
    [Why_It_Matters]    [varchar](500)      NULL,
    [What_To_Do]        [varchar](500)      NULL,
    [Records_Affected]  [int]           NOT NULL,
    [Population]        [int]               NULL,   -- the denominator, e.g. active patients
    [Pct_Affected]      [decimal](5,2)      NULL,   -- NULL when the population is 0
    [Has_Issue]         [bit]           NOT NULL,   -- 1 when Records_Affected > 0
    [Display_Order]     [int]           NOT NULL,
    [DW_Created_At]     [datetime2](6)  NOT NULL,
    [DW_Updated_At]     [datetime2](6)  NOT NULL
)
GO
