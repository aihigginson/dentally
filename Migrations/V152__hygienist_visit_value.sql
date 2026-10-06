-- V152: a per-visit value that moves plan revenue from the dentist to the hygienist.
--
-- A plan patient's hygienist visit costs them nothing: the capitation fee covers it. Today every
-- penny of that fee is credited to the DENTIST (Gold.usp_Load_Fact_Revenue posts capitation to
-- Dim_Patients.Dentist_Practitioner_ID), so a hygienist seeing ~3,400 plan patients a year earns
-- nothing from any of them. The owner settles this per visit in practice; the warehouse has never
-- reflected it.
--
-- So: one owner-entered amount PER PLAN, effective-dated, and every completed hygienist visit by a
-- member generates a matched pair of Fact_Revenue rows -- the dentist debited, the hygienist
-- credited, the same figure. Total capitation is unchanged, which matters because that total is
-- already right; only its attribution moves.
--
-- ==> IT SITS ON THE EXISTING RATE ROW, NOT A NEW TABLE. <== Input.Plan_Capitation_Rate is already
-- keyed (Tenant_ID, Payment_Plan_ID, Effective_From_Date) and already carries "the latest rate
-- effective on or before the month wins" semantics in Gold.usp_Load_Fact_Revenue. Putting the
-- visit value beside the monthly fee means one rate history, one effective date to reason about,
-- and a rate change next April cannot retrospectively rewrite this year's split. A separate table
-- would be a second history to keep in step with the first.
--
-- ==> NULLABLE, AND NULL MEANS "DO NOTHING". <== No existing row has a value, so until the owner
-- enters one the whole mechanism produces no rows at all. That is the intended state on the day
-- this ships: the plumbing is in, nothing moves, and nobody's revenue changes by accident.
--
-- ==> EXPECT IT TO EXCEED THE MONTHLY FEE. <== A plan covers one or two hygienist visits a YEAR,
-- so a sensible per-visit figure is a multiple of the monthly charge -- DECIMAL(9,2) like
-- Monthly_Value, no tighter. Do not add a CHECK tying it below the monthly fee; that would be
-- wrong in the ordinary case.
--
-- ==> APPDB FIRST, WAREHOUSE SECOND, AND THE ORDER IS LOAD-BEARING. <== Web/appdb_sync.py reads
-- the column list from WH Input_Stage and SELECTs exactly those columns from AppDB. Add the column
-- to Input_Stage before AppDB has it and every run of that ten-minute job fails on an invalid
-- column name until someone notices. This migration is the first half; the warehouse half is a
-- release.
--
-- ALTER, never DROP/CREATE: this table holds the owner's curated rates, which exist nowhere else.

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Input.Plan_Capitation_Rate')
                 AND name = 'Hygienist_Visit_Value')
    ALTER TABLE Input.Plan_Capitation_Rate ADD Hygienist_Visit_Value DECIMAL(9,2) NULL;
GO

SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Plan_Capitation_Rate'
ORDER BY ORDINAL_POSITION;
