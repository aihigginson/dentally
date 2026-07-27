--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Treatment_Plan_Items] @Tenant_ID=11, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Treatment_Plan_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     18/05/2026  AIH Fix ID to VARCHAR(50) for UUID keys; load all Stage columns;
--                            handle True/False boolean strings for Charged/Completed
--    *04     19/05/2026  AIH Remove treatment_name from COALESCE (not in API); add Surfaces, Teeth
--    *05     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
--  To Run           :   DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
--                        EXEC Bronze.usp_Load_Treatment_Plan_Items @Tenant_ID=11, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Treatment_Plan_Items]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Treatment_Plan_Items]
(
      @Tenant_ID    INT
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
              TRY_CAST(tenant_id   AS INT)                                             AS Tenant_ID
            , LEFT(CAST(id AS VARCHAR(50)), 50)                                         AS ID
            , LEFT(treatment_plan_id,            255)                                   AS Treatment_Plan_ID
            , TRY_CAST(patient_id      AS DECIMAL(18,4))                               AS Patient_ID
            , TRY_CAST(practitioner_id AS INT)                                         AS Practitioner_ID
            , TRY_CAST(treatment_id    AS DECIMAL(18,4))                               AS Treatment_ID
            , LEFT(CAST(nomenclature AS VARCHAR(255)), 255)                            AS Nomenclature
            , TRY_CAST(price            AS DECIMAL(18,4))                              AS Price
            , TRY_CAST(duration         AS DECIMAL(18,4))                              AS Duration
            , LEFT(created_at,           255)                                          AS Created_At
            , LEFT(updated_at,           255)                                          AS Updated_At
            , LEFT(appear_on_invoice, 255)                                              AS Appear_On_Invoice
            -- Real Dentally sends base_chart as boolean ('True'/'False'); map -> 1/0 (numeric fallback).
            , CASE WHEN LOWER(LTRIM(RTRIM(base_chart))) IN ('true','1')  THEN 1
                   WHEN LOWER(LTRIM(RTRIM(base_chart))) IN ('false','0') THEN 0
                   ELSE TRY_CAST(base_chart AS DECIMAL(18,4)) END                       AS Base_Chart
            , LEFT(charged,          255)                                              AS Charged
            , LEFT(completed,        255)                                              AS Completed
            , LEFT(completed_at,         255)                                          AS Completed_At
            , LEFT(invoice_id,           255)                                          AS Invoice_ID
            , LEFT(nhs_treatment_cat,    255)                                          AS NHS_Treatment_Cat
            , TRY_CAST(payment_plan_id   AS INT)                                       AS Payment_Plan_ID
            , TRY_CAST(position          AS DECIMAL(18,4))                             AS Position
            , TRY_CAST(referrer_id       AS DECIMAL(18,4))                             AS Referrer_ID
            , LEFT(region,               255)                                          AS Region
            , LEFT(treatment_appointment_id, 255)                                      AS Treatment_Appointment_ID
            , LEFT(uda_band,             255)                                          AS UDA_Band
            , LEFT(surfaces, 255) AS Surfaces
            , LEFT(teeth,    255) AS Teeth
        INTO #src
        FROM Stage.Treatment_Plan_Items
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID
          AND id IS NOT NULL;

        UPDATE tgt SET
              tgt.Treatment_Plan_ID        = src.Treatment_Plan_ID
            , tgt.Patient_ID               = src.Patient_ID
            , tgt.Practitioner_ID          = src.Practitioner_ID
            , tgt.Treatment_ID             = src.Treatment_ID
            , tgt.Nomenclature             = src.Nomenclature
            , tgt.Price                    = src.Price
            , tgt.Duration                 = src.Duration
            , tgt.Created_At               = src.Created_At
            , tgt.Updated_At               = src.Updated_At
            , tgt.Appear_On_Invoice        = src.Appear_On_Invoice
            , tgt.Base_Chart               = src.Base_Chart
            , tgt.Charged                  = src.Charged
            , tgt.Completed                = src.Completed
            , tgt.Completed_At             = src.Completed_At
            , tgt.Invoice_ID               = src.Invoice_ID
            , tgt.NHS_Treatment_Cat        = src.NHS_Treatment_Cat
            , tgt.Payment_Plan_ID          = src.Payment_Plan_ID
            , tgt.Position                 = src.Position
            , tgt.Referrer_ID              = src.Referrer_ID
            , tgt.Region                   = src.Region
            , tgt.Treatment_Appointment_ID = src.Treatment_Appointment_ID
            , tgt.UDA_Band                 = src.UDA_Band
            , tgt.Surfaces                 = src.Surfaces
            , tgt.Teeth                    = src.Teeth
            , tgt.DW_Loaded_At             = SYSUTCDATETIME()
        FROM Bronze.Treatment_Plan_Items AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Treatment_Plan_Items (
            Tenant_ID, ID, Treatment_Plan_ID, Patient_ID, Practitioner_ID, Treatment_ID,
            Nomenclature, Price, Duration, Created_At, Updated_At,
            Appear_On_Invoice, Base_Chart, Charged, Completed, Completed_At,
            Invoice_ID, NHS_Treatment_Cat, Payment_Plan_ID,
            Position, Referrer_ID, Region, Treatment_Appointment_ID, UDA_Band,
            Surfaces, Teeth,
            DW_Loaded_At
        )
        SELECT
            src.Tenant_ID, src.ID, src.Treatment_Plan_ID, src.Patient_ID, src.Practitioner_ID, src.Treatment_ID,
            src.Nomenclature, src.Price, src.Duration, src.Created_At, src.Updated_At,
            src.Appear_On_Invoice, src.Base_Chart, src.Charged, src.Completed, src.Completed_At,
            src.Invoice_ID, src.NHS_Treatment_Cat, src.Payment_Plan_ID,
            src.Position, src.Referrer_ID, src.Region, src.Treatment_Appointment_ID, src.UDA_Band,
            src.Surfaces, src.Teeth,
            SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Treatment_Plan_Items tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;


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
