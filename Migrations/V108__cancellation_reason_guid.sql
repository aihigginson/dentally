-- V108__cancellation_reason_guid.sql
-- Real Dentally appointment_cancellation_reason_id is a GUID; Bronze.Appointments typed it INT
-- (built for the mock's integer IDs), so TRY_CAST(... AS INT) nulled every real GUID and no
-- cancellation reason ever resolved for real tenants. Change the column to VARCHAR(50).
--
-- Fabric can't ALTER COLUMN int->varchar, and Bronze.Appointments is DROP/CREATE, so swap the column
-- IN PLACE (preserves the 247k rows) rather than rebuild+re-ingest: add a varchar column, drop the
-- int one, rename. Idempotent -- only runs while the column is still int.
-- (Bronze.Cancellation_Reasons / Gold.Dim_Cancellation_Reasons already hold the real GUID reasons,
-- and Gold.Fact_Appointments already joins on the string bk, so this column is the only break.)
-- NOTE: existing rows' reason stays NULL until a re-ingest re-pulls appointments through the fixed
-- Bronze.usp_Load_Appointments (init_stage retains only the latest delta, not full history).
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA='Bronze' AND TABLE_NAME='Appointments'
             AND COLUMN_NAME='Appointment_Cancellation_Reason_ID' AND DATA_TYPE='int')
BEGIN
    ALTER TABLE Bronze.Appointments ADD Appointment_Cancellation_Reason_ID_v2 varchar(50) NULL;
    ALTER TABLE Bronze.Appointments DROP COLUMN Appointment_Cancellation_Reason_ID;
    EXEC sp_rename 'Bronze.Appointments.Appointment_Cancellation_Reason_ID_v2', 'Appointment_Cancellation_Reason_ID', 'COLUMN';
END
GO
