-- V148: add Cutover_Date to Audit.Tenants WITHOUT dropping the table (its tenant rows survive; the
-- table no longer holds secrets -- those moved to the MS key store -- but a data-preserving ALTER is
-- still the clean way to add the column on an existing environment). Cutover_Date = the tenant's
-- Dentally go-live, derived as MIN(Updated_At) of Treatment Plans by Audit.usp_Set_Tenant_Cutover
-- (Updated_At is stamped by Dentally, not by migrated history). Guarded so it is a no-op where the
-- column was already added by hand (dev). A fresh build gets the column from the updated Table.sql.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Audit.Tenants') AND name = 'Cutover_Date')
    ALTER TABLE Audit.Tenants ADD Cutover_Date date NULL;
GO
