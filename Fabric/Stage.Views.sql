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

DROP VIEW IF EXISTS [Stage].[Practice]
GO
CREATE VIEW [Stage].[Practice] AS
SELECT * FROM LH_Dentally.dbo.stage_practice
GO

DROP VIEW IF EXISTS [Stage].[Treatment_Categories]
GO
CREATE VIEW [Stage].[Treatment_Categories] AS
SELECT * FROM LH_Dentally.dbo.stage_treatment_categories
GO

DROP VIEW IF EXISTS [Stage].[Acquisition_Sources]
GO
CREATE VIEW [Stage].[Acquisition_Sources] AS
SELECT * FROM LH_Dentally.dbo.stage_acquisition_sources
GO

DROP VIEW IF EXISTS [Stage].[Sundries]
GO
CREATE VIEW [Stage].[Sundries] AS
SELECT * FROM LH_Dentally.dbo.stage_sundries
GO

DROP VIEW IF EXISTS [Stage].[Contracts]
GO
CREATE VIEW [Stage].[Contracts] AS
SELECT * FROM LH_Dentally.dbo.stage_contracts
GO

DROP VIEW IF EXISTS [Stage].[Fees]
GO
CREATE VIEW [Stage].[Fees] AS
SELECT * FROM LH_Dentally.dbo.stage_fees
GO

DROP VIEW IF EXISTS [Stage].[Practitioner_Diary_Breaks]
GO
CREATE VIEW [Stage].[Practitioner_Diary_Breaks] AS
SELECT * FROM LH_Dentally.dbo.stage_practitioner_diary_breaks
GO

DROP VIEW IF EXISTS [Stage].[NHS_Claims]
GO
CREATE VIEW [Stage].[NHS_Claims] AS
SELECT * FROM LH_Dentally.dbo.stage_nhs_claims
GO

DROP VIEW IF EXISTS [Stage].[Patient_Stats]
GO
CREATE VIEW [Stage].[Patient_Stats] AS
SELECT * FROM LH_Dentally.dbo.stage_patient_stats
GO

DROP VIEW IF EXISTS [Stage].[Payment_Allocations]
GO
CREATE VIEW [Stage].[Payment_Allocations] AS
SELECT * FROM LH_Dentally.dbo.stage_payment_allocations
GO

DROP VIEW IF EXISTS [Stage].[Payment_Explanations]
GO
CREATE VIEW [Stage].[Payment_Explanations] AS
SELECT * FROM LH_Dentally.dbo.stage_payment_explanations
GO

DROP VIEW IF EXISTS [Stage].[Treatment_Appointments]
GO
CREATE VIEW [Stage].[Treatment_Appointments] AS
SELECT * FROM LH_Dentally.dbo.stage_treatment_appointments
GO
