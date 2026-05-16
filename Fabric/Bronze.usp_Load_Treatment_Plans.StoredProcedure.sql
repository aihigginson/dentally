--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Treatment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Treatment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Treatment_Plans]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Treatment_Plans]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
    , @Logging      SMALLINT         = 1
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
    DECLARE @My_Run_UUID VARCHAR(36);
    DECLARE @My_Error    VARCHAR(4000);
    SET NOCOUNT ON;
    IF @Logging = 1
        EXEC Audit.ETL_Start_Run
            @Run_Process_Name    = 'Bronze.usp_Load_Treatment_Plans',
            @Run_Process_Options = CONCAT('@Tenant_ID = ', @Tenant_ID, ', @Full_Refresh = ', @Full_Refresh),
            @Run_UUID            = @My_Run_UUID OUTPUT,
            @Parent_Run_UUID     = ISNULL(CONVERT(VARCHAR(36), @Run_UUID), '00000000-0000-0000-0000-000000000000');

    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id                AS INT)           AS Tenant_ID
            , TRY_CAST(id                       AS DECIMAL(18,4)) AS ID
            , TRY_CAST(patient_id               AS DECIMAL(18,4)) AS Patient_ID
            , TRY_CAST(practitioner_id          AS INT)           AS Practitioner_ID
            , TRY_CAST(nhs_uda_value            AS DECIMAL(18,4)) AS NHS_UDA_Value
            , TRY_CAST(nhs_completed_uda_value  AS DECIMAL(18,4)) AS NHS_Completed_UDA_Value
            , TRY_CAST(private_treatment_value  AS DECIMAL(18,4)) AS Private_Treatment_Value
            , LEFT(created_at,                    255)            AS Created_At
            , LEFT(updated_at,                    255)            AS Updated_At
        INTO #src
        FROM Stage.Treatment_Plans
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID                = src.Patient_ID
            , tgt.Practitioner_ID           = src.Practitioner_ID
            , tgt.NHS_UDA_Value             = src.NHS_UDA_Value
            , tgt.NHS_Completed_UDA_Value   = src.NHS_Completed_UDA_Value
            , tgt.Private_Treatment_Value   = src.Private_Treatment_Value
            , tgt.Created_At                = src.Created_At
            , tgt.Updated_At                = src.Updated_At
            , tgt.DW_Loaded_At              = SYSUTCDATETIME()
        FROM Bronze.Treatment_Plans AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Treatment_Plans (Tenant_ID, ID, Patient_ID, Practitioner_ID, NHS_UDA_Value, NHS_Completed_UDA_Value, Private_Treatment_Value, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Patient_ID, src.Practitioner_ID, src.NHS_UDA_Value, src.NHS_Completed_UDA_Value, src.Private_Treatment_Value, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Treatment_Plans tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Treatment_Plans AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

        IF @Logging = 1
            EXEC Audit.ETL_Finish_Run
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'SUCCEEDED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes;
    END TRY
    BEGIN CATCH
        IF @Logging = 1
        BEGIN
            SET @My_Error = Audit.ETL_Error_Handler();
            EXEC Audit.ETL_Finish_Run
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'FAILED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes,
                @Error         = @My_Error;
        END
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
