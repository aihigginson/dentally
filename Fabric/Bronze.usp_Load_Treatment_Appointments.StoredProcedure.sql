--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Treatment_Appointments
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Treatment_Appointments]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Treatment_Appointments]
(
      @Tenant_ID    INT
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
    , @Full_Refresh BIT    = 0
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                          AS Tenant_ID
            , LEFT(id, 255)                                       AS ID
            , CASE WHEN bookable IN ('True', '1', 'true') THEN 1 ELSE 0 END AS Bookable
            , LEFT(notes, 4000)                                   AS Notes
            , TRY_CAST(position AS INT)                           AS Position
            , LEFT(created_at, 255)                               AS Created_At
            , LEFT(updated_at, 255)                               AS Updated_At
            , TRY_CAST(appointment_id AS INT)                     AS Appointment_ID
            , TRY_CAST(patient_id AS INT)                         AS Patient_ID
            , TRY_CAST(treatment_plan_id AS INT)                  AS Treatment_Plan_ID
        INTO #src
        FROM Stage.Treatment_Appointments
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Bookable          = src.Bookable
            , tgt.Notes             = src.Notes
            , tgt.Position          = src.Position
            , tgt.Appointment_ID    = src.Appointment_ID
            , tgt.Patient_ID        = src.Patient_ID
            , tgt.Treatment_Plan_ID = src.Treatment_Plan_ID
            , tgt.Updated_At        = src.Updated_At
            , tgt.DW_Loaded_At      = SYSUTCDATETIME()
        FROM Bronze.Treatment_Appointments AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Treatment_Appointments (Tenant_ID, ID, Bookable, Notes, Position, Created_At, Updated_At, Appointment_ID, Patient_ID, Treatment_Plan_ID, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Bookable, src.Notes, src.Position, src.Created_At, src.Updated_At, src.Appointment_ID, src.Patient_ID, src.Treatment_Plan_ID, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Treatment_Appointments tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Treatment_Appointments AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH THROW; END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
