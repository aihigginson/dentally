/****** Object:  Table [Input].[Client_Region]    Script Date: 24/10/2026 ******/
-- A client's regions. Surrogate key, born in AppDB.
--
-- Full-refreshed from Input_Stage.Client_Region by Meta.usp_Sync_Input_From_AppDB; AppDB is the
-- source of truth. Shape generated from the staging DDL, which was itself generated
-- from the live AppDB schema.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Input].[Client_Region]
GO
CREATE TABLE [Input].[Client_Region](
    [Region_ID]      [int]              NOT NULL,
    [Client_ID]      [int]              NOT NULL,
    [Region_Name]    [varchar](100)     NOT NULL,
    [Sort_Order]     [int]              NOT NULL,
    [Is_Active]      [bit]              NOT NULL,
    [Updated_At]     [datetime2](3)     NOT NULL,
    [Updated_By]     [varchar](256)     NULL
)
GO
