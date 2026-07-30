-- =====================================================================
-- V124 -- Fix invoice-fact under-load after V117's DROP/CREATE.
-- V117 DROP/CREATE'd Gold.Fact_Invoices + Fact_Invoice_Items (accounts excision) but left their
-- Gold.Load_Watermark rows at "now". The watermark-incremental load then only reloaded rows changed
-- since -> 22 / 57 rows instead of 49,523 / 91,208, collapsing all revenue onto a single date.
-- Reset the watermark so the next load (build or manual EXEC) does a FULL reload. The load SPs
-- deployed alongside this migration also gain an empty-table safety net to prevent recurrence.
-- =====================================================================
DELETE FROM Gold.Load_Watermark WHERE Entity_Name IN ('Fact_Invoices', 'Fact_Invoice_Items');
GO
