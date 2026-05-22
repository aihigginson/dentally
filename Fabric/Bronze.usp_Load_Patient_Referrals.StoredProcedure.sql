--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Patient_Referrals] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Patient_Referrals
--  Author           :  AIH
--  Initital Date    :  15/05/2026
--  History          :
--    *01     15/05/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Patient_Referrals @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Patient_Referrals]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Patient_Referrals]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts  BIGINT = 0;
    DECLARE @My_Updates  BIGINT = 0;
    DECLARE @My_Deletes  BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id                 AS INT)           AS Tenant_ID
            , TRY_CAST(id                        AS INT)           AS ID
            , TRY_CAST(patient_id                AS DECIMAL(18,4)) AS Patient_ID
            , LEFT(site_id,                        255)            AS Site_ID
            , TRY_CAST(user_id                   AS DECIMAL(18,4)) AS User_ID
            , LEFT(reference,                      255)            AS Reference
            , LEFT(status,                         255)            AS Status
            , LEFT(referrable_type,                255)            AS Referrable_Type
            , LEFT(services_appointment_id,        255)            AS Services_Appointment_ID
            , CAST(additional_information        AS VARCHAR(MAX))  AS Additional_Information
            , LEFT(CAST(consented_by_patient     AS VARCHAR(10)), 10) AS Consented_By_Patient
            , TRY_CAST(referred_practitioner_id  AS DECIMAL(18,4)) AS Referred_Practitioner_ID
            , LEFT(referred_site_id,               255)            AS Referred_Site_ID
            , LEFT(created_at,                     255)            AS Created_At
            , LEFT(updated_at,                     255)            AS Updated_At
        INTO #src
        FROM Stage.Patient_Referrals
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID               = src.Patient_ID
            , tgt.Site_ID                  = src.Site_ID
            , tgt.User_ID                  = src.User_ID
            , tgt.Reference                = src.Reference
            , tgt.Status                   = src.Status
            , tgt.Referrable_Type          = src.Referrable_Type
            , tgt.Services_Appointment_ID  = src.Services_Appointment_ID
            , tgt.Additional_Information   = src.Additional_Information
            , tgt.Consented_By_Patient     = src.Consented_By_Patient
            , tgt.Referred_Practitioner_ID = src.Referred_Practitioner_ID
            , tgt.Referred_Site_ID         = src.Referred_Site_ID
            , tgt.Updated_At               = src.Updated_At
            , tgt.DW_Loaded_At             = SYSUTCDATETIME()
        FROM Bronze.Patient_Referrals AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Patient_Referrals (
            Tenant_ID, ID, Patient_ID, Site_ID, User_ID, Reference, Status,
            Referrable_Type, Services_Appointment_ID, Additional_Information,
            Consented_By_Patient, Referred_Practitioner_ID, Referred_Site_ID,
            Created_At, Updated_At, DW_Loaded_At
        )
        SELECT
            src.Tenant_ID, src.ID, src.Patient_ID, src.Site_ID, src.User_ID, src.Reference, src.Status,
            src.Referrable_Type, src.Services_Appointment_ID, src.Additional_Information,
            src.Consented_By_Patient, src.Referred_Practitioner_ID, src.Referred_Site_ID,
            src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Patient_Referrals tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Patient_Referrals AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
