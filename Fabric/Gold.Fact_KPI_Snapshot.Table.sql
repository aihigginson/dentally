--------------------------------------------------------------------
--  Table   : Gold.Fact_KPI_Snapshot
--  Author  : AIH
--  Date    : 18/05/2026
--  Purpose : Generic point-in-time KPI snapshot.
--            Stores one row per (Tenant, Site, Practitioner, Metric,
--            fk_Date, Snapshot_Grain).
--            Snapshot_Grain: 'weekly'  = every Friday
--                            'monthly' = last calendar day of each month
--            Site-level and practice-level totals are aggregations in DAX;
--            no separate rollup rows are stored.
--            Current metrics loaded: open_courses_value, retention_outlook
--            Additional metrics can be appended to usp_Load_Fact_KPI_Snapshot
--            without schema changes.
--------------------------------------------------------------------
/****** Object:  Table [Gold].[Fact_KPI_Snapshot]    Script Date: 18/05/2026 ******/

DROP TABLE IF EXISTS [Gold].[Fact_KPI_Snapshot]
GO
CREATE TABLE [Gold].[Fact_KPI_Snapshot]
(
    [pk_KPI_Snapshot]   BIGINT IDENTITY NOT NULL,
    [Tenant_ID]         INT             NOT NULL,
    [Site_ID]           VARCHAR(50)     NULL,
    [fk_Practice_Site]  BIGINT          NULL,
    [fk_Practitioner]   BIGINT          NULL,
    [Metric]            VARCHAR(100)    NOT NULL,
    [fk_Date]           INT             NOT NULL,
    [Snapshot_Grain]    VARCHAR(10)     NOT NULL,
    [Value]             DECIMAL(18,4)   NOT NULL,
    [DW_Created_At]     DATETIME2(3)    NOT NULL
)
GO
