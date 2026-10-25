/****** Object:  Table [Input].[Client_Area]    Script Date: 24/10/2026 ******/
-- A region's areas. Client reached through Region_ID, never stored twice.
--
-- Full-refreshed from Input_Stage.Client_Area by Meta.usp_Sync_Input_From_AppDB; AppDB is the
-- source of truth. Shape generated from the staging DDL, which was itself generated
-- from the live AppDB schema.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Input].[Client_Area]
GO
CREATE TABLE [Input].[Client_Area](
    [Area_ID]        [int]              NOT NULL,
    [Region_ID]      [int]              NOT NULL,
    [Area_Name]      [varchar](100)     NOT NULL,
    [Sort_Order]     [int]              NOT NULL,
    [Is_Active]      [bit]              NOT NULL,
    [Updated_At]     [datetime2](3)     NOT NULL,
    [Updated_By]     [varchar](256)     NULL
)
GO
