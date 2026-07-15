-- V096__dim_practitioner_fte.sql
-- Add Gold.Dim_Practitioners.FTE (per-practitioner FTE from Input.Practitioner_Pay, default 1.0)
-- for FTE-scaled target measures. ALTER (dim upserts; not a rebuild).
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA='Gold' AND TABLE_NAME='Dim_Practitioners' AND COLUMN_NAME='FTE')
    EXEC('ALTER TABLE Gold.Dim_Practitioners ADD FTE DECIMAL(4,2) NULL');
GO
