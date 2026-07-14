-- V087__dim_practitioner_custom_role.sql
-- Add Gold.Dim_Practitioners.Custom_Role via ALTER (NOT a table DROP/CREATE) so pk_Practitioner
-- is preserved and fact fk_Practitioner is not orphaned. Populated by the load SP as
-- Custom_Role = COALESCE(Input.Practitioner_Role override, Dentally role). Idempotent.
-- (Fabric warehouse: COL_LENGTH unsupported -> use INFORMATION_SCHEMA; EXEC() defers the DDL.)
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Gold' AND TABLE_NAME = 'Dim_Practitioners' AND COLUMN_NAME = 'Custom_Role')
    EXEC('ALTER TABLE Gold.Dim_Practitioners ADD Custom_Role VARCHAR(100) NULL');
GO
