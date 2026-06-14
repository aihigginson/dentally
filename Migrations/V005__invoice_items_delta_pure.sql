-- ===========================================================================
-- V005  invoice_items_delta_pure
-- ---------------------------------------------------------------------------
-- Removes the two DERIVED columns from Gold.Fact_Invoice_Items so the table holds
-- only source-derived data (delta == full refresh):
--   * Aged_Debt_Band  -- time-derived; now computed LIVE in Gold.vw_Fact_Invoice_Items.
--   * Is_Discount     -- the sparse exception; now a tiny positive table
--                        (Gold.Invoice_Discount) LEFT JOINed in the view, rather than
--                        a per-row flag + per-invoice window forced onto every line.
--
-- Guarded + forward-only. The Gold.Invoice_Discount table is created from its own
-- object script (guarded create); this migration only drops the columns.
-- ===========================================================================

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Invoice_Items') AND name = 'Aged_Debt_Band')
    ALTER TABLE Gold.Fact_Invoice_Items DROP COLUMN [Aged_Debt_Band];
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Invoice_Items') AND name = 'Is_Discount')
    ALTER TABLE Gold.Fact_Invoice_Items DROP COLUMN [Is_Discount];
GO
