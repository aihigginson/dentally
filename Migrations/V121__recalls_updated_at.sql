-- =====================================================================
-- V121 -- Recalls incremental extract: capture Updated_At in Bronze so the Dentally ingest pulls
-- recalls with an updated_after watermark (like patients/appointments/invoices/...) instead of a
-- FULL load every run. The real recalls API returns updated_at and it already lands in Stage.Recalls;
-- Bronze simply never stored it, so recalls was absent from the ingest watermark (WM) dict.
--
-- ALTER (not DROP/CREATE) to PRESERVE the existing recall rows. On existing rows Updated_At is NULL,
-- so the first run's watermark = MAX(NULL) = none -> one cold full pull repopulates Updated_At ->
-- every subsequent run is incremental. Pairs with the keep-latest prune (V118).
-- The Bronze.usp_Load_Recalls DEPLOY (this manifest) then reads updated_at from Stage into the column.
-- =====================================================================
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Bronze' AND TABLE_NAME = 'Recalls' AND COLUMN_NAME = 'Updated_At')
    ALTER TABLE Bronze.Recalls ADD Updated_At VARCHAR(255) NULL;
GO
