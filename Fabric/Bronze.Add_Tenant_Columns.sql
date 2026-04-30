-- =============================================================================
-- Add Tenant_ID and DW_Loaded_At to all Bronze tables
-- =============================================================================
-- Run once against WH_Dentally in the Fabric web query editor.
-- These columns are also added to the CREATE TABLE scripts for future deploys.
-- =============================================================================

ALTER TABLE Bronze.Sites               ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Users               ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Practitioners       ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Payment_Plans       ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Treatments          ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Patients            ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Accounts            ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Appointments        ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Invoices            ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Invoice_Items       ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Payments            ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Treatment_Plans     ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Treatment_Plan_Items ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Recalls             ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
ALTER TABLE Bronze.Practitioner_Diary  ADD Tenant_ID INT NULL, DW_Loaded_At DATETIME2(3) NULL; GO
