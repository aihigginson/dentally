--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Accounts
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Accounts @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Accounts]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Accounts]
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
              TRY_CAST(tenant_id                      AS INT)   AS Tenant_ID
            , TRY_CAST(id                             AS INT)   AS Account_ID
            , TRY_CAST(patient_id                     AS INT)   AS Patient_ID
            , LEFT(patient_name,                        255)    AS Patient_Name
            , LEFT(current_balance,                     255)    AS Current_Balance
            , LEFT(opening_balance,                     255)    AS Opening_Balance
            , LEFT(planned_nhs_treatment_value,         255)    AS Planned_NHS_Treatment_Value
            , LEFT(planned_private_treatment_value,     255)    AS Planned_Private_Treatment_Value
        INTO #src
        FROM Stage.Accounts
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID                      = src.Patient_ID
            , tgt.Patient_Name                    = src.Patient_Name
            , tgt.Current_Balance                 = src.Current_Balance
            , tgt.Opening_Balance                 = src.Opening_Balance
            , tgt.Planned_NHS_Treatment_Value     = src.Planned_NHS_Treatment_Value
            , tgt.Planned_Private_Treatment_Value = src.Planned_Private_Treatment_Value
            , tgt.DW_Loaded_At                    = SYSUTCDATETIME()
        FROM Bronze.Accounts AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Account_ID = src.Account_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Accounts (Tenant_ID, Account_ID, Patient_ID, Patient_Name, Current_Balance, Opening_Balance, Planned_NHS_Treatment_Value, Planned_Private_Treatment_Value, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Account_ID, src.Patient_ID, src.Patient_Name, src.Current_Balance, src.Opening_Balance, src.Planned_NHS_Treatment_Value, src.Planned_Private_Treatment_Value, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Accounts tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Account_ID = src.Account_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Accounts AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Account_ID = tgt.Account_ID);
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
