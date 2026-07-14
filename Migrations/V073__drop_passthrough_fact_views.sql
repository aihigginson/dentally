-- =====================================================================
-- V073 -- Remove the two pure-passthrough Gold views
-- =====================================================================
-- Gold.vw_Fact_Treatment_Plans and Gold.vw_Fact_Invoice_Items were hand-written
-- "1-1 passthrough" views with a HARDCODED column list. They carry no logic
-- (no joins / CASE / date derivations -- unlike vw_Dim_Invoices, vw_Fact_Payments,
-- vw_Fact_Appointment_Journey, which do and are kept). Because a Gold vw_<X> view
-- SUPERSEDES the table in Meta.usp_Create_Gold_Views, these frozen lists silently
-- dropped columns appended to the fact later (Course_Status,
-- Private_Treatment_Value_Outstanding, ...). That left PBI.[_Treatment Plans]
-- missing columns -> every plan measure errored -> the semantic-model refresh failed
-- -> the whole report stayed stale.
--
-- Fix: drop the two overrides. The generator then builds PBI.[_Treatment Plans] and
-- PBI.[_Invoice Items] directly from the Fact tables via sys.columns (the catalogue),
-- so they always carry every column. Regenerate the PBI views to apply immediately.
-- Verified on dev: PBI.[_Treatment Plans] 18 -> 25 cols (Course Status + Outstanding present).
-- =====================================================================

DROP VIEW IF EXISTS [Gold].[vw_Fact_Treatment_Plans];
GO
DROP VIEW IF EXISTS [Gold].[vw_Fact_Invoice_Items];
GO
EXEC [Meta].[usp_Create_Gold_Views];
GO
