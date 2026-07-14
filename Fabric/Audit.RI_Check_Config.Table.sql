/****** Object:  Table [Audit].[RI_Check_Config] ******/
-- Fact->Dim relationships checked by Audit.usp_Check_Referential_Integrity. A config table
-- (not sys.* -- Fabric forbids system-view queries inside a proc's distributed processing).
-- Regenerate the seed from live metadata with the client-side enumeration query in
-- Audit.RI_Check_Config.Data.sql's header; add a row when a new fact fk_* is introduced.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[RI_Check_Config]
GO
CREATE TABLE [Audit].[RI_Check_Config](
    [Fact_Table] [varchar](128) NOT NULL,
    [FK_Column]  [varchar](128) NOT NULL,
    [Dim_Table]  [varchar](128) NOT NULL,   -- target table (a Gold dim, or a fact for fact-to-fact refs)
    [PK_Column]  [varchar](128) NOT NULL,
    [Is_Active]  [bit]          NOT NULL
)
GO
-- Persisted RI-check output (a permanent table, not #temp -- Fabric rejects temp tables inside
-- the dynamic SQL that drives the checks). One row per violation/warning per run; the latest run
-- is a durable audit of integrity. usp_Check_Referential_Integrity clears + repopulates it.
DROP TABLE IF EXISTS [Audit].[RI_Check_Result]
GO
CREATE TABLE [Audit].[RI_Check_Result](
    [Checked_At] [datetime2](3) NOT NULL,
    [Kind]       [varchar](12)  NOT NULL,   -- SENTINEL | ORPHAN | WARN_M1
    [Obj]        [varchar](200) NOT NULL,
    [Detail]     [varchar](400) NOT NULL,
    [Bad_Count]  [bigint]       NOT NULL
)
GO
