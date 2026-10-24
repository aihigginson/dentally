/****** Object:  Table [Input].[Client]    Script Date: 24/10/2026 ******/
-- The client we sell to and then serve. Client_ID matches Audit.Tenants.Client_ID.
--
-- Full-refreshed from Input_Stage.Client by Meta.usp_Sync_Input_From_AppDB; AppDB is the
-- source of truth. Shape generated from the staging DDL, which was itself generated
-- from the live AppDB schema.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Input].[Client]
GO
CREATE TABLE [Input].[Client](
    [Client_ID]      [int]              NOT NULL,
    [Client_Name]    [varchar](255)     NOT NULL,
    [Is_Active]      [bit]              NOT NULL,
    [Updated_At]     [datetime2](3)     NOT NULL,
    [Updated_By]     [varchar](256)     NULL
)
GO
