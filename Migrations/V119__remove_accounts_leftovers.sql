-- =====================================================================
-- V119 -- Remove the last Dentally patient-Accounts excision leftovers (V117 follow-up).
-- V117 dropped Gold.Dim_Accounts + fk_Account, but three references survived and broke the
-- build's integrity-check step ("Invalid object name 'Gold.Dim_Accounts'"):
--   1. Audit.RI_Check_Config still asserted Fact_Invoices/Fact_Invoice_Items.fk_Account -> Dim_Accounts
--   2. Test.Metric_Definition had a FK-null check on the dropped Fact_Invoice_Items.fk_Account
--   3. an orphaned Stage.Accounts view (its stage_accounts source is no longer extracted)
-- (1) + (2) are re-seeded by the DEPLOY actions in this manifest (both files DELETE/TRUNCATE + re-INSERT);
-- (3)'s source file no longer creates the view, so this migration drops the copy left in the warehouse.
-- The Xero GL Account / Finance family (Xero_Accounts, Dim_GL_Account) is unrelated and untouched.
-- =====================================================================
DROP VIEW IF EXISTS [Stage].[Accounts];
GO
