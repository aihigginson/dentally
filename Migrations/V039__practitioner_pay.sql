-- V039 -- Input.Practitioner_Pay: per-practitioner associate pay share (% of production).
-- Idempotent create so a re-deploy never drops the table / wipes admin-entered values.
IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'Input' AND t.name = 'Practitioner_Pay')
EXEC('
CREATE TABLE [Input].[Practitioner_Pay] (
    [pk_practitioner_pay] BIGINT        IDENTITY NOT NULL,
    [Tenant_ID]           INT           NOT NULL,
    [Practitioner_ID]     INT           NOT NULL,
    [Associate_Pct]       DECIMAL(6,3)  NOT NULL,
    [DW_Created_At]       DATETIME2(3)  NOT NULL,
    [DW_Updated_At]       DATETIME2(3)  NOT NULL
)');
