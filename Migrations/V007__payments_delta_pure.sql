-- ===========================================================================
-- V007  payments_delta_pure
-- ---------------------------------------------------------------------------
-- Decouples the deposit (the rare exception) from Gold.Fact_Payments so the fact
-- holds only source-derived per-payment data (a clean single-source delta):
--   * Is_Deposit / Deposit_Amount -> moved to the tiny positive table
--     Gold.Payment_Deposit (only payments with a deposit), LEFT JOINed in
--     Gold.vw_Fact_Payments. This removes the cross-entity dependency (deposit
--     depends on Treatment_Plans.Completed etc.) from the fact table.
--
-- Guarded + forward-only. Gold.Payment_Deposit is created from its own object
-- script; this migration only drops the columns.
-- ===========================================================================

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Payments') AND name = 'Is_Deposit')
    ALTER TABLE Gold.Fact_Payments DROP COLUMN [Is_Deposit];
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Payments') AND name = 'Deposit_Amount')
    ALTER TABLE Gold.Fact_Payments DROP COLUMN [Deposit_Amount];
GO
