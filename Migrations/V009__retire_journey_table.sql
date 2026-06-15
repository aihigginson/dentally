-- ===========================================================================
-- V009  retire_journey_table
-- ---------------------------------------------------------------------------
-- The appointment journey derivation (Booking + Appointment_Reason -- the two
-- static columns left after V008) is now folded directly into
-- Gold.usp_Load_Fact_Appointments (a #journey preamble). The separate Silver
-- derived table, its load proc, and its pipeline step are retired, so Silver
-- goes back to holding only cleaned source data.
--
-- This migration drops the now-unused table. Forward-only.
-- ===========================================================================

IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
           WHERE s.name = 'Silver' AND t.name = 'Appointment_Journey_Attributes')
    DROP TABLE Silver.Appointment_Journey_Attributes;
GO
