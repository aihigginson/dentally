--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Payment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     19/05/2026  AIH Fix scale_polish_duration->scale_and_polish_duration; add active, created_at, colour, emergency_duration, exam_scale_and_polish_duration, patient_friendly_name, site_id
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Payment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Payment_Plans]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Payment_Plans]
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
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id               AS INT)            AS Tenant_ID
            , TRY_CAST(id                      AS INT)            AS Payment_Plan_ID
            , LEFT(name,                          255)            AS Payment_Plan_Name
            , TRY_CAST(dentist_recall_interval  AS DECIMAL(18,4)) AS Dentist_Recall_Interval
            , TRY_CAST(hygienist_recall_interval AS DECIMAL(18,4)) AS Hygienist_Recall_Interval
            , TRY_CAST(exam_duration            AS DECIMAL(18,4)) AS Exam_Duration
            , TRY_CAST(scale_and_polish_duration AS DECIMAL(18,4)) AS Scale_And_Polish_Duration
            , CASE WHEN LOWER(CAST(active AS VARCHAR(10))) IN ('true','1') THEN CAST(1.0 AS DECIMAL(18,4)) ELSE CAST(0.0 AS DECIMAL(18,4)) END AS Payment_Plan_Active
            , LEFT(created_at,              255) AS Payment_Plan_Created_At
            , LEFT(colour,                  255) AS Payment_Plan_Colour
            , TRY_CAST(emergency_duration   AS DECIMAL(18,4)) AS Emergency_Duration
            , TRY_CAST(exam_scale_and_polish_duration AS DECIMAL(18,4)) AS Exam_Scale_And_Polish_Duration
            , LEFT(patient_friendly_name,   255) AS Payment_Plan_Patient_Friendly_Name
            , LEFT(site_id,                 255) AS Payment_Plan_Site_ID
        INTO #src
        FROM Stage.Payment_Plans
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Payment_Plan_Name                  = src.Payment_Plan_Name
            , tgt.Dentist_Recall_Interval             = src.Dentist_Recall_Interval
            , tgt.Hygienist_Recall_Interval           = src.Hygienist_Recall_Interval
            , tgt.Exam_Duration                       = src.Exam_Duration
            , tgt.Scale_And_Polish_Duration           = src.Scale_And_Polish_Duration
            , tgt.Payment_Plan_Active                 = src.Payment_Plan_Active
            , tgt.Payment_Plan_Created_At             = src.Payment_Plan_Created_At
            , tgt.Payment_Plan_Colour                 = src.Payment_Plan_Colour
            , tgt.Emergency_Duration                  = src.Emergency_Duration
            , tgt.Exam_Scale_And_Polish_Duration      = src.Exam_Scale_And_Polish_Duration
            , tgt.Payment_Plan_Patient_Friendly_Name  = src.Payment_Plan_Patient_Friendly_Name
            , tgt.Payment_Plan_Site_ID                = src.Payment_Plan_Site_ID
            , tgt.DW_Loaded_At                        = SYSUTCDATETIME()
        FROM Bronze.Payment_Plans AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Payment_Plan_ID = src.Payment_Plan_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Payment_Plans (Tenant_ID, Payment_Plan_ID, Payment_Plan_Name, Dentist_Recall_Interval, Hygienist_Recall_Interval, Exam_Duration, Scale_And_Polish_Duration, Payment_Plan_Active, Payment_Plan_Created_At, Payment_Plan_Colour, Emergency_Duration, Exam_Scale_And_Polish_Duration, Payment_Plan_Patient_Friendly_Name, Payment_Plan_Site_ID, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Payment_Plan_ID, src.Payment_Plan_Name, src.Dentist_Recall_Interval, src.Hygienist_Recall_Interval, src.Exam_Duration, src.Scale_And_Polish_Duration, src.Payment_Plan_Active, src.Payment_Plan_Created_At, src.Payment_Plan_Colour, src.Emergency_Duration, src.Exam_Scale_And_Polish_Duration, src.Payment_Plan_Patient_Friendly_Name, src.Payment_Plan_Site_ID, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Payment_Plans tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Payment_Plan_ID = src.Payment_Plan_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Payment_Plans AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Payment_Plan_ID = tgt.Payment_Plan_ID);
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
