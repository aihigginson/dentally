-- ===========================================================================
-- V002  gold_load_watermark
-- ---------------------------------------------------------------------------
-- Infrastructure for incremental (watermark-driven) Gold loads. Holds the last
-- successful load timestamp per Gold entity; a delta load processes only Silver
-- rows with DW_Updated_At > Last_Loaded_At.
--
-- Data-bearing -> guarded create (a redeploy must not wipe watermarks; losing a
-- row only forces a one-off full reload, but we avoid even that). Forward-only.
-- ===========================================================================

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
               WHERE s.name = 'Gold' AND t.name = 'Load_Watermark')
    CREATE TABLE Gold.Load_Watermark (
        [Entity_Name]    varchar(128)  NOT NULL,
        [Last_Loaded_At] datetime2(3)  NOT NULL,
        [DW_Updated_At]  datetime2(3)  NULL
    );
GO
