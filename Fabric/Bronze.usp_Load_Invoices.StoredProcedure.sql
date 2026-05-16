--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Invoices
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Invoices @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Invoices]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Invoices]
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
              TRY_CAST(tenant_id          AS INT)          AS Tenant_ID
            , TRY_CAST(id                 AS INT)          AS ID
            , TRY_CAST(patient_id         AS INT)          AS Patient_ID
            , TRY_CAST(account_id         AS INT)          AS Account_ID
            , LEFT(site_id,                 255)           AS Site_ID
            , TRY_CAST(user_id            AS INT)          AS User_ID
            , TRY_CAST(amount             AS DECIMAL(18,4)) AS Amount
            , TRY_CAST(amount_outstanding AS DECIMAL(18,4)) AS Amount_Outstanding
            , LEFT(nhs_amount,              255)           AS NHS_Amount
            , LEFT(dated_on,                255)           AS Dated_On
            , LEFT(due_on,                  255)           AS Due_On
            , TRY_CAST(paid               AS DECIMAL(18,4)) AS Paid
            , LEFT(paid_on,                 255)           AS Paid_On
            , LEFT(reference,               255)           AS Reference
            , LEFT(footnote,                255)           AS Footnote
            , LEFT(created_at,              255)           AS Created_At
            , LEFT(updated_at,              255)           AS Updated_At
        INTO #src
        FROM Stage.Invoices
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID          = src.Patient_ID
            , tgt.Account_ID          = src.Account_ID
            , tgt.Site_ID             = src.Site_ID
            , tgt.User_ID             = src.User_ID
            , tgt.Amount              = src.Amount
            , tgt.Amount_Outstanding  = src.Amount_Outstanding
            , tgt.NHS_Amount          = src.NHS_Amount
            , tgt.Dated_On            = src.Dated_On
            , tgt.Due_On              = src.Due_On
            , tgt.Paid                = src.Paid
            , tgt.Paid_On             = src.Paid_On
            , tgt.Reference           = src.Reference
            , tgt.Footnote            = src.Footnote
            , tgt.Created_At          = src.Created_At
            , tgt.Updated_At          = src.Updated_At
            , tgt.DW_Loaded_At        = SYSUTCDATETIME()
        FROM Bronze.Invoices AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Invoices (Tenant_ID, ID, Patient_ID, Account_ID, Site_ID, User_ID, Amount, Amount_Outstanding, NHS_Amount, Dated_On, Due_On, Paid, Paid_On, Reference, Footnote, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Patient_ID, src.Account_ID, src.Site_ID, src.User_ID, src.Amount, src.Amount_Outstanding, src.NHS_Amount, src.Dated_On, src.Due_On, src.Paid, src.Paid_On, src.Reference, src.Footnote, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Invoices tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Invoices AS tgt
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
