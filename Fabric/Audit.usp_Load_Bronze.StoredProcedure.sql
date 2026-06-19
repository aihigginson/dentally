--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Audit].[usp_Load_Bronze] @Tenant_ID=1, @Full_Refresh=0, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Load_Bronze
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     29/04/2026  AIH Added 11 new Bronze entity load procedures
--    *07     20/05/2026  AIH Add Rooms entity
--    *05     16/05/2026  AIH Add Audit ETL logging; accumulate totals from children
--    *06     16/05/2026  AIH Rewrite to use Audit.ETL_Run_Process pattern matching
--                           Audit.usp_Load_All; Process_Config drives per-entity
--                           per-tenant calls (240 rows: 30 entities x 8 tenants)
--    *07     19/06/2026  AIH One Process_Config job per table: codes are now BRONZE_{ENTITY}
--                           (31 rows, not 248); tenant + full-refresh passed as runtime params
--                           to ETL_Run_Process (resolves {TID}/{FR} tokens). Also threads
--                           @Full_Refresh through (previously dropped on this path).
--    *08     19/06/2026  AIH Moved Bronze.usp_Load_All -> Audit.usp_Load_Bronze: it is an ETL
--                           orchestrator (sibling of Audit.usp_Load_All), not a Bronze data SP.
--  To Run           :   DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Audit].[usp_Load_Bronze] @Tenant_ID=1, @Full_Refresh=0, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Audit].[usp_Load_Bronze]
GO
CREATE PROCEDURE [Audit].[usp_Load_Bronze]
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

    DECLARE @Run_Process_Name    VARCHAR(1000) = 'Audit.usp_Load_Bronze';
    DECLARE @Run_Process_Options VARCHAR(1000) = CONCAT('@Tenant_ID = ', @Tenant_ID, ', @Full_Refresh = ', CAST(@Full_Refresh AS INT));
    DECLARE @Parent_Run_UUID     VARCHAR(36)   = CONVERT(VARCHAR(36), @Run_UUID);
    DECLARE @Process_Code        VARCHAR(100);
    DECLARE @Step                VARCHAR(100);

    EXEC [Audit].[ETL_Start_Run]
        @Run_Process_Name,
        @Run_Process_Options,
        @Run_UUID OUT,
        @Parent_Run_UUID,
        'PROCEDURE';

    SET @Parent_Run_UUID = CONVERT(VARCHAR(36), @Run_UUID);

    BEGIN TRY

        -- ── Reference data (always full refresh in source) ─────────────────────
        SET @Step = 'Practice';                   SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Sites';                      SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Users';                      SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Practitioners';              SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Payment_Plans';              SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Treatments';                 SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Treatment_Categories';       SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Acquisition_Sources';        SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Cancellation_Reasons';       SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Rooms';                      SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Waiting_Lists';              SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Sundries';                   SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Contracts';                  SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Fees';                       SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Practitioner_Diary_Breaks';  SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;

        -- ── Transactional data ────────────────────────────────────────────────
        SET @Step = 'Patients';                   SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Accounts';                   SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Appointments';               SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Invoices';                   SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Invoice_Items';              SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Payments';                   SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Treatment_Plans';            SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Treatment_Plan_Items';       SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Recalls';                    SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Practitioner_Diary_Entries'; SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'NHS_Claims';                 SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Patient_Stats';              SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Payment_Allocations';        SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Payment_Explanations';       SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Treatment_Appointments';     SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;
        SET @Step = 'Patient_Referrals';          SET @Process_Code = 'BRONZE_' + UPPER(@Step); EXEC Audit.ETL_Run_Process @Process_Code, @Parent_Run_UUID, @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh;

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
