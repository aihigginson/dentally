/****** Object:  Table [Input].[Client_Tenant]    Script Date: 24/10/2026 ******/
-- Which client a tenant belongs to. One client per tenant.
--
-- Full-refreshed from Input_Stage.Client_Tenant by Meta.usp_Sync_Input_From_AppDB; AppDB is the
-- source of truth. Shape generated from the staging DDL, which was itself generated
-- from the live AppDB schema.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Input].[Client_Tenant]
GO
CREATE TABLE [Input].[Client_Tenant](
    [Tenant_ID]      [int]              NOT NULL,
    [Client_ID]      [int]              NOT NULL,
    [Updated_At]     [datetime2](3)     NOT NULL,
    [Updated_By]     [varchar](256)     NULL
)
GO
