-- Stage views: thin wrappers over LH_Dentally lakehouse Delta tables.
-- Bronze usp_Load_* procs read from these views at execution time.
-- LH_Dentally must be in the same Fabric workspace as WH_Dentally.

DROP VIEW IF EXISTS [Stage].[Sites]
GO
CREATE VIEW [Stage].[Sites] AS
SELECT * FROM LH_Dentally.dbo.stage_sites
GO

DROP VIEW IF EXISTS [Stage].[Users]
GO
CREATE VIEW [Stage].[Users] AS
SELECT * FROM LH_Dentally.dbo.stage_users
GO

DROP VIEW IF EXISTS [Stage].[Practitioners]
GO
CREATE VIEW [Stage].[Practitioners] AS
SELECT * FROM LH_Dentally.dbo.stage_practitioners
GO

DROP VIEW IF EXISTS [Stage].[Payment_Plans]
GO
CREATE VIEW [Stage].[Payment_Plans] AS
SELECT * FROM LH_Dentally.dbo.stage_payment_plans
GO

DROP VIEW IF EXISTS [Stage].[Treatments]
GO
CREATE VIEW [Stage].[Treatments] AS
SELECT * FROM LH_Dentally.dbo.stage_treatments
GO

DROP VIEW IF EXISTS [Stage].[Patients]
GO
CREATE VIEW [Stage].[Patients] AS
SELECT * FROM LH_Dentally.dbo.stage_patients
GO

DROP VIEW IF EXISTS [Stage].[Accounts]
GO
CREATE VIEW [Stage].[Accounts] AS
SELECT * FROM LH_Dentally.dbo.stage_accounts
GO

DROP VIEW IF EXISTS [Stage].[Appointments]
GO
CREATE VIEW [Stage].[Appointments] AS
SELECT * FROM LH_Dentally.dbo.stage_appointments
GO

DROP VIEW IF EXISTS [Stage].[Invoices]
GO
CREATE VIEW [Stage].[Invoices] AS
SELECT * FROM LH_Dentally.dbo.stage_invoices
GO

DROP VIEW IF EXISTS [Stage].[Invoice_Items]
GO
CREATE VIEW [Stage].[Invoice_Items] AS
SELECT * FROM LH_Dentally.dbo.stage_invoice_items
GO

DROP VIEW IF EXISTS [Stage].[Payments]
GO
CREATE VIEW [Stage].[Payments] AS
SELECT * FROM LH_Dentally.dbo.stage_payments
GO

DROP VIEW IF EXISTS [Stage].[Treatment_Plans]
GO
CREATE VIEW [Stage].[Treatment_Plans] AS
SELECT * FROM LH_Dentally.dbo.stage_treatment_plans
GO

DROP VIEW IF EXISTS [Stage].[Treatment_Plan_Items]
GO
CREATE VIEW [Stage].[Treatment_Plan_Items] AS
SELECT * FROM LH_Dentally.dbo.stage_treatment_plan_items
GO

DROP VIEW IF EXISTS [Stage].[Recalls]
GO
CREATE VIEW [Stage].[Recalls] AS
SELECT * FROM LH_Dentally.dbo.stage_recalls
GO

DROP VIEW IF EXISTS [Stage].[Practitioner_Diary_Entries]
GO
CREATE VIEW [Stage].[Practitioner_Diary_Entries] AS
SELECT * FROM LH_Dentally.dbo.stage_practitioner_diary_entries
GO

-- -----------------------------------------------------------------------
-- The views below reference LH_Dentally Delta tables that are created by
-- Stage_Ingest.  On a fresh environment those tables do not exist until
-- Stage_Ingest has run at least once, so each CREATE VIEW is wrapped in
-- TRY/CATCH and executed via EXEC() (which puts CREATE VIEW first in its
-- own sub-batch).  A warning is printed for any that are skipped.
-- Re-deploying this file (a DEPLOY step) after Stage_Ingest will create them.
-- -----------------------------------------------------------------------

BEGIN TRY
    IF OBJECT_ID('[Stage].[Practice]', 'V') IS NOT NULL DROP VIEW [Stage].[Practice];
    EXEC('CREATE VIEW [Stage].[Practice] AS SELECT * FROM LH_Dentally.dbo.stage_practice');
    PRINT 'Created Stage.Practice';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Practice skipped — stage_practice not yet in LH_Dentally (run Stage_Ingest first)';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Treatment_Categories]', 'V') IS NOT NULL DROP VIEW [Stage].[Treatment_Categories];
    EXEC('CREATE VIEW [Stage].[Treatment_Categories] AS SELECT * FROM LH_Dentally.dbo.stage_treatment_categories');
    PRINT 'Created Stage.Treatment_Categories';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Treatment_Categories skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Acquisition_Sources]', 'V') IS NOT NULL DROP VIEW [Stage].[Acquisition_Sources];
    EXEC('CREATE VIEW [Stage].[Acquisition_Sources] AS SELECT * FROM LH_Dentally.dbo.stage_acquisition_sources');
    PRINT 'Created Stage.Acquisition_Sources';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Acquisition_Sources skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Cancellation_Reasons]', 'V') IS NOT NULL DROP VIEW [Stage].[Cancellation_Reasons];
    EXEC('CREATE VIEW [Stage].[Cancellation_Reasons] AS SELECT * FROM LH_Dentally.dbo.stage_cancellation_reasons');
    PRINT 'Created Stage.Cancellation_Reasons';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Cancellation_Reasons skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Waiting_Lists]', 'V') IS NOT NULL DROP VIEW [Stage].[Waiting_Lists];
    EXEC('CREATE VIEW [Stage].[Waiting_Lists] AS SELECT * FROM LH_Dentally.dbo.stage_waiting_lists');
    PRINT 'Created Stage.Waiting_Lists';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Waiting_Lists skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Sundries]', 'V') IS NOT NULL DROP VIEW [Stage].[Sundries];
    EXEC('CREATE VIEW [Stage].[Sundries] AS SELECT * FROM LH_Dentally.dbo.stage_sundries');
    PRINT 'Created Stage.Sundries';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Sundries skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Contracts]', 'V') IS NOT NULL DROP VIEW [Stage].[Contracts];
    EXEC('CREATE VIEW [Stage].[Contracts] AS SELECT * FROM LH_Dentally.dbo.stage_contracts');
    PRINT 'Created Stage.Contracts';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Contracts skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Fees]', 'V') IS NOT NULL DROP VIEW [Stage].[Fees];
    EXEC('CREATE VIEW [Stage].[Fees] AS SELECT * FROM LH_Dentally.dbo.stage_fees');
    PRINT 'Created Stage.Fees';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Fees skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Practitioner_Diary_Breaks]', 'V') IS NOT NULL DROP VIEW [Stage].[Practitioner_Diary_Breaks];
    EXEC('CREATE VIEW [Stage].[Practitioner_Diary_Breaks] AS SELECT * FROM LH_Dentally.dbo.stage_practitioner_diary_breaks');
    PRINT 'Created Stage.Practitioner_Diary_Breaks';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Practitioner_Diary_Breaks skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[NHS_Claims]', 'V') IS NOT NULL DROP VIEW [Stage].[NHS_Claims];
    EXEC('CREATE VIEW [Stage].[NHS_Claims] AS SELECT * FROM LH_Dentally.dbo.stage_nhs_claims');
    PRINT 'Created Stage.NHS_Claims';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.NHS_Claims skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Patient_Stats]', 'V') IS NOT NULL DROP VIEW [Stage].[Patient_Stats];
    EXEC('CREATE VIEW [Stage].[Patient_Stats] AS SELECT * FROM LH_Dentally.dbo.stage_patient_stats');
    PRINT 'Created Stage.Patient_Stats';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Patient_Stats skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Payment_Allocations]', 'V') IS NOT NULL DROP VIEW [Stage].[Payment_Allocations];
    EXEC('CREATE VIEW [Stage].[Payment_Allocations] AS SELECT * FROM LH_Dentally.dbo.stage_payment_allocations');
    PRINT 'Created Stage.Payment_Allocations';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Payment_Allocations skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Payment_Explanations]', 'V') IS NOT NULL DROP VIEW [Stage].[Payment_Explanations];
    EXEC('CREATE VIEW [Stage].[Payment_Explanations] AS SELECT * FROM LH_Dentally.dbo.stage_payment_explanations');
    PRINT 'Created Stage.Payment_Explanations';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Payment_Explanations skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Treatment_Appointments]', 'V') IS NOT NULL DROP VIEW [Stage].[Treatment_Appointments];
    EXEC('CREATE VIEW [Stage].[Treatment_Appointments] AS SELECT * FROM LH_Dentally.dbo.stage_treatment_appointments');
    PRINT 'Created Stage.Treatment_Appointments';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Treatment_Appointments skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Patient_Referrals]', 'V') IS NOT NULL DROP VIEW [Stage].[Patient_Referrals];
    EXEC('CREATE VIEW [Stage].[Patient_Referrals] AS SELECT * FROM LH_Dentally.dbo.stage_patient_referrals');
    PRINT 'Created Stage.Patient_Referrals';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Patient_Referrals skipped — run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Rooms]', 'V') IS NOT NULL DROP VIEW [Stage].[Rooms];
    EXEC('CREATE VIEW [Stage].[Rooms] AS SELECT * FROM LH_Dentally.dbo.stage_rooms');
    PRINT 'Created Stage.Rooms';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Rooms skipped -- run Stage_Ingest first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Xero_Accounts]', 'V') IS NOT NULL DROP VIEW [Stage].[Xero_Accounts];
    EXEC('CREATE VIEW [Stage].[Xero_Accounts] AS SELECT * FROM LH_Dentally.dbo.stage_xero_accounts');
    PRINT 'Created Stage.Xero_Accounts';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Xero_Accounts skipped -- run API/xero_land.py first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Xero_Lines]', 'V') IS NOT NULL DROP VIEW [Stage].[Xero_Lines];
    EXEC('CREATE VIEW [Stage].[Xero_Lines] AS SELECT * FROM LH_Dentally.dbo.stage_xero_lines');
    PRINT 'Created Stage.Xero_Lines';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Xero_Lines skipped -- run API/xero_land.py first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Xero_Orgs]', 'V') IS NOT NULL DROP VIEW [Stage].[Xero_Orgs];
    EXEC('CREATE VIEW [Stage].[Xero_Orgs] AS SELECT * FROM LH_Dentally.dbo.stage_xero_orgs');
    PRINT 'Created Stage.Xero_Orgs';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Xero_Orgs skipped -- run API/xero_land.py first';
END CATCH;
GO

BEGIN TRY
    IF OBJECT_ID('[Stage].[Xero_Tracking]', 'V') IS NOT NULL DROP VIEW [Stage].[Xero_Tracking];
    EXEC('CREATE VIEW [Stage].[Xero_Tracking] AS SELECT * FROM LH_Dentally.dbo.stage_xero_tracking');
    PRINT 'Created Stage.Xero_Tracking';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Xero_Tracking skipped -- run API/xero_land.py first';
END CATCH;
GO
