--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Fact_Payments
--  Author           :  AIH
--  Initial Date     :  22/05/2026
--  History          :
--    *01     22/05/2026  AIH  Initial Release
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Create_Fact_Payments @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Payments]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Payments]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

    DROP TABLE IF EXISTS Gold.Fact_Payments;

    CREATE TABLE Gold.Fact_Payments (
        pk_Payment          BIGINT          NOT NULL IDENTITY,
        Tenant_ID           INT             NOT NULL,
        bk_Payment_ID       INT             NOT NULL,
        fk_Patient          BIGINT          NULL,
        fk_Practitioner     BIGINT          NULL,
        fk_Practice_Site    BIGINT          NULL,
        fk_Date_Payment     BIGINT          NULL,
        Payment_Method      VARCHAR(100)    NULL,
        Payment_Amount      DECIMAL(12,2)   NULL,
        Is_Deposit          BIT             NULL,
        Deposit_Amount      DECIMAL(12,2)   NULL,
        DW_Created_At       datetime2(6)    NOT NULL,
        DW_Updated_At       datetime2(6)    NOT NULL
    );

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes
END
GO
