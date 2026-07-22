-- V110__patient_standard_payment_plan.sql
-- Patients-by-Plan (My Data): denormalise the standardised payment-plan name onto Gold.Dim_Patients
-- so patients can be sliced by plan WITHOUT a model relationship. A natural-key relationship
-- (List Patients[Payment Plan ID] -> List Payment Plans) can't be used: Payment_Plan_ID is
-- per-tenant, so it would fan out across tenants. The name is carried on the patient row instead.
--
-- Adds the column IN PLACE (idempotent) so the existing 170k+ patient rows are preserved -- the
-- table is a hash-gated upsert, not truncate-load. The updated usp_Load_Dim_Patients (deployed in
-- the same manifest, AFTER this) now includes Standard_Payment_Plan in the change hash, so the next
-- load UPDATEs every existing row to populate it. Runs once per environment (tracked MIGRATE).
--
-- MUST precede the SP deploy: Fabric validates all referenced columns at CREATE time, so the SP
-- won't create until this column exists.
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'Gold' AND TABLE_NAME = 'Dim_Patients'
      AND COLUMN_NAME = 'Standard_Payment_Plan'
)
    ALTER TABLE Gold.Dim_Patients ADD Standard_Payment_Plan varchar(100) NULL;
GO
