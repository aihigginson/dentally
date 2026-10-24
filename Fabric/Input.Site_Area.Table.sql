/****** Object:  Table [Input].[Site_Area]    Script Date: 24/10/2026 ******/
-- Where each SITE sits. The grain is the site, not the tenant: one tenant may span areas, which is the whole reason the tree hangs off the site.
--
-- Full-refreshed from Input_Stage.Site_Area by Meta.usp_Sync_Input_From_AppDB; AppDB is the
-- source of truth. Shape generated from the staging DDL, which was itself generated
-- from the live AppDB schema.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Input].[Site_Area]
GO
CREATE TABLE [Input].[Site_Area](
    [Tenant_ID]      [int]              NOT NULL,
    [Site_ID]        [varchar](50)      NOT NULL,
    [Area_ID]        [int]              NOT NULL,
    [Updated_At]     [datetime2](3)     NOT NULL,
    [Updated_By]     [varchar](256)     NULL
)
GO
