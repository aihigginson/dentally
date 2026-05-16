--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_All] @Tenant_ID=1, @Full_Refresh=0, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_All
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     29/04/2026  AIH Added 11 new Bronze entity load procedures
--    *05     16/05/2026  AIH Add Audit ETL logging; accumulate totals from children
--    *06     16/05/2026  AIH Rewrite to use Audit.ETL_Run_Process pattern matching
--                           Audit.usp_Load_All; Process_Config drives per-entity
--                           per-tenant calls (240 rows: 30 entities x 8 tenants)
--  To Run           :   DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_All] @Tenant_ID=1, @Full_Refresh=0, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_All]
GO
CREATE PROCEDURE [Bronze].[usp_Load_All]
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
    SET NOCOUNT ON;

    DECLARE @Run_Process_Name    VARCHAR(1000) = 'Bronze.usp_Load_All';
    DECLARE @Run_Process_Options VARCHAR(1000) = CONCAT('@Tenant_ID = ', @Tenant_ID, ', @Full_Refresh = ', CAST(@Full_Refresh AS INT));
    DECLARE @Parent_Run_UUID     VARCHAR(36)   = CONVERT(VARCHAR(36), @Run_UUID);
    DECLARE @Process_Code        VARCHAR(100);
    DECLARE @Step                VARCHAR(100);
    DECLARE @TID                 VARCHAR(4)    = CAST(@Tenant_ID AS VARCHAR);

    EXEC [Audit].[ETL_Start_Run]
        @Run_Process_Name,
        @Run_Process_Options,
        @Run_UUID OUT,
        @Parent_Run_UUID,
        'PROCEDURE';

    SET @Parent_Run_UUID = CONVERT(VARCHAR(36), @Run_UUID);

    BEGIN TRY

        -- ── Reference data (always full refresh in source) ─────────────────────
        SET @Step = 'Practice';                   SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Sites';                      SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Users';                      SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Practitioners';              SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Payment_Plans';              SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Treatments';                 SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Treatment_Categories';       SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Acquisition_Sources';        SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Cancellation_Reasons';       SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Waiting_Lists';              SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Sundries';                   SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Contracts';                  SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Fees';                       SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Practitioner_Diary_Breaks';  SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;

        -- ── Transactional data ────────────────────────────────────────────────
        SET @Step = 'Patients';                   SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Accounts';                   SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Appointments';               SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Invoices';                   SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Invoice_Items';              SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Payments';                   SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Treatment_Plans';            SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Treatment_Plan_Items';       SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Recalls';                    SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Practitioner_Diary_Entries'; SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'NHS_Claims';                 SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Patient_Stats';              SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Payment_Allocations';        SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Payment_Explanations';       SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Treatment_Appointments';     SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;
        SET @Step = 'Patient_Referrals';          SET @Process_Code = 'BRONZE_T' + @TID + '_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID;

        EXEC [Audit].[ETL_Finish_Run] @Run_UUID, 'SUCCEEDED', 0, 0, 0, 'Success', '';

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = 0;
    SET @Run_Updates = 0;
    SET @Run_Deletes = 0;
END
GO
