/****** Object:  Table [Gold].[Aggregate_Practitioner_Day_Book] ******/
-- Per-practitioner Day Book action counts, held as TEXT so they can sit in a matrix's ROW area
-- (alongside List Practitioners[Full Name], Stepped Layout = Off) and scroll WITH the diary-fill
-- heatmap in the SAME visual -- no independent-scroll desync. GOLD_AGG (reads facts) so the build
-- orders it after the facts/current aggregate; NOT columns on Dim_Practitioners (that would make a
-- dimension read facts). Each count matches its Day Book detail page's filter.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Practitioner_Day_Book]
GO
CREATE TABLE [Gold].[Aggregate_Practitioner_Day_Book](
    [Tenant_ID]                 [int]          NOT NULL,
    [fk_Practitioner]           [bigint]       NOT NULL,
    [Open_Plans]                [varchar](10)  NULL,  -- Course_Status IN (In Progress, Open - No Appointment)
    [Cancellations_To_Rebook]   [varchar](10)  NULL,  -- Is_Cancelled + Rebooked_Status = Not Rebooked
    [DNAs_To_Rebook]            [varchar](10)  NULL,  -- Is_DNA + Rebooked_Status = Not Rebooked
    [Recalls_To_Action]         [varchar](10)  NULL,  -- Retention_Outlook_In_Scope=1 + Is_Booked=0
    [Days_Until_Next_30_Free]   [varchar](10)  NULL,  -- MIN days to next 30-min free slot
    [DW_Created_At]             [datetime2](6) NOT NULL,
    [DW_Updated_At]             [datetime2](6) NOT NULL
)
GO
