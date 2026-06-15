-- ===========================================================================
-- V008  appointments_journey_to_dax
-- ---------------------------------------------------------------------------
-- Drops the three RELATIONSHIP / time-derived journey columns from the
-- appointment tables. They move to DAX (computed from the appointment
-- self-relationship + Recalls, with an Include/Exclude hygiene toggle):
--   * Delay            -- banded gap to the next appointment
--   * Next_Appointment -- reason of the next appointment
--   * Current_State     -- post-visit status (relationship + recall, simplified
--                          to "In Recall Process"; recall detail -> its own report)
-- Booking + Appointment_Reason stay (static, on the table).
--
-- Guarded + forward-only. Silver.Appointment_Journey_Attributes is full-recompute
-- so its structure is also refreshed by its table object script; the Fact table
-- is altered in place here. NOTE: PBI.[_Appointments Sankey] (built from these
-- columns) is removed in Meta.usp_Create_Gold_Views and will be rebuilt in DAX.
-- ===========================================================================

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Silver.Appointment_Journey_Attributes') AND name = 'Delay')
    ALTER TABLE Silver.Appointment_Journey_Attributes DROP COLUMN [Delay];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Silver.Appointment_Journey_Attributes') AND name = 'Next_Appointment')
    ALTER TABLE Silver.Appointment_Journey_Attributes DROP COLUMN [Next_Appointment];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Silver.Appointment_Journey_Attributes') AND name = 'Current_State')
    ALTER TABLE Silver.Appointment_Journey_Attributes DROP COLUMN [Current_State];
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Appointments') AND name = 'Delay')
    ALTER TABLE Gold.Fact_Appointments DROP COLUMN [Delay];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Appointments') AND name = 'Next_Appointment')
    ALTER TABLE Gold.Fact_Appointments DROP COLUMN [Next_Appointment];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Appointments') AND name = 'Current_State')
    ALTER TABLE Gold.Fact_Appointments DROP COLUMN [Current_State];
GO
