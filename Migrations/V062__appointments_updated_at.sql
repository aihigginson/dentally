-- =============================================================================
-- V062 -- re-add Updated_At to Bronze.Appointments
-- =============================================================================
-- The *06 removal ("not in Dentally API") was wrong -- updated_at IS in the appointments API
-- (same mistake as the Site_ID one). Adding it lets appointments delta on updated_after via the
-- per-tenant Bronze watermark instead of a fixed-window full re-pull. ALTER (not table recreate)
-- so synthetic-tenant rows survive; existing rows get Updated_At = NULL, which makes the watermark
-- NULL -> the next appointments pull is a COLD start (windowed from 2021, cancelled=true) that
-- backfills the missing cancelled/DNA appointments and lands Updated_At.
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Bronze.Appointments') AND name = 'Updated_At')
    ALTER TABLE [Bronze].[Appointments] ADD [Updated_At] VARCHAR(255) NULL;
GO
