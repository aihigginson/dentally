--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Payments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Payments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Payments]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Payments]
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
              TRY_CAST(tenant_id          AS INT)           AS Tenant_ID
            , TRY_CAST(id                 AS DECIMAL(18,4)) AS Payment_ID
            , TRY_CAST(account_id         AS DECIMAL(18,4)) AS Account_ID
            , TRY_CAST(patient_id         AS DECIMAL(18,4)) AS Patient_ID
            , LEFT(site_id,                 255)            AS Site_ID
            , TRY_CAST(payment_plan_id    AS INT)           AS Payment_Plan_ID
            , TRY_CAST(practitioner_id    AS INT)           AS Practitioner_ID
            , TRY_CAST(user_id            AS INT)           AS User_ID
            , TRY_CAST(amount             AS DECIMAL(18,4)) AS Amount
            , TRY_CAST(amount_unexplained AS DECIMAL(18,4)) AS Amount_Unexplained
            , LEFT(dated_on,                255)            AS Dated_On
            , LEFT(method,                  255)            AS Method
            , TRY_CAST(reference          AS DECIMAL(18,4)) AS Reference
            , LEFT(status,                  255)            AS Status
            , TRY_CAST(deleted            AS DECIMAL(18,4)) AS Deleted
            , TRY_CAST(fully_explained    AS DECIMAL(18,4)) AS Fully_Explained
            , TRY_CAST(transaction_number AS DECIMAL(18,4)) AS Transaction_Number
        INTO #src
        FROM Stage.Payments
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Account_ID         = src.Account_ID
            , tgt.Patient_ID         = src.Patient_ID
            , tgt.Site_ID            = src.Site_ID
            , tgt.Payment_Plan_ID    = src.Payment_Plan_ID
            , tgt.Practitioner_ID    = src.Practitioner_ID
            , tgt.User_ID            = src.User_ID
            , tgt.Amount             = src.Amount
            , tgt.Amount_Unexplained = src.Amount_Unexplained
            , tgt.Dated_On           = src.Dated_On
            , tgt.Method             = src.Method
            , tgt.Reference          = src.Reference
            , tgt.Status             = src.Status
            , tgt.Deleted            = src.Deleted
            , tgt.Fully_Explained    = src.Fully_Explained
            , tgt.Transaction_Number = src.Transaction_Number
            , tgt.DW_Loaded_At       = SYSUTCDATETIME()
        FROM Bronze.Payments AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Payment_ID = src.Payment_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Payments (Tenant_ID, Payment_ID, Account_ID, Patient_ID, Site_ID, Payment_Plan_ID, Practitioner_ID, User_ID, Amount, Amount_Unexplained, Dated_On, Method, Reference, Status, Deleted, Fully_Explained, Transaction_Number, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Payment_ID, src.Account_ID, src.Patient_ID, src.Site_ID, src.Payment_Plan_ID, src.Practitioner_ID, src.User_ID, src.Amount, src.Amount_Unexplained, src.Dated_On, src.Method, src.Reference, src.Status, src.Deleted, src.Fully_Explained, src.Transaction_Number, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Payments tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Payment_ID = src.Payment_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Payments AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Payment_ID = tgt.Payment_ID);
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
