--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Fact_Invoice_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Fact_Invoice_Items @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Invoice_Items]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Invoice_Items]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    -- Local counters
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;    
    SET NOCOUNT ON;    
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

    DROP TABLE IF EXISTS Gold.Fact_Invoice_Items;

      CREATE TABLE Gold.Fact_Invoice_Items (
        pk_Invoice_Item             BIGINT              NOT NULL IDENTITY,
        Tenant_ID                      INT             NOT NULL,
        bk_Invoice_Item_ID          VARCHAR(50)        NOT NULL,   -- Natural key

        fk_Patient                  BIGINT              NULL,
        fk_Practitioner             BIGINT              NULL,
        fk_Payment_Plan             BIGINT              NULL,
        fk_Treatment_Plan           BIGINT              NULL,
        fk_Account                  BIGINT              NULL,
        fk_Practice_Site            BIGINT              NULL,
        fk_User                     BIGINT              NULL,

        fk_Date_Invoice             BIGINT              NULL,
        fk_Date_Due                 BIGINT              NULL,
        fk_Date_Paid                BIGINT              NULL,
        fk_Date_Created             BIGINT              NULL,

        Invoice_ID                  INT                 NULL,
        Treatment_Plan_Item_ID      VARCHAR(50)        NULL,
        Sundry_ID                   INT                 NULL,

        Item_Name                   VARCHAR(255)       NULL,
        Invoice_Reference           VARCHAR(50)        NULL,
        Invoice_Payment_Terms       VARCHAR(255)       NULL,
        Invoice_Footnote            VARCHAR(MAX)       NULL,
        Invoice_Paid                BIT                 NULL,

        Item_Price                  DECIMAL(18,4)       NULL,
        Quantity                    INT                 NULL,
        Total_Price                 DECIMAL(18,4)       NULL,
        NHS_Charge                  BIT                 NULL,
        Invoice_Amount              DECIMAL(18,4)       NULL,
        Invoice_Amount_Outstanding  DECIMAL(18,4)       NULL,
        Invoice_NHS_Amount          DECIMAL(18,4)       NULL,
        Aged_Debt_Band              VARCHAR(20)         NULL,

        DW_Created_At               datetime2(6)        NOT NULL,
        DW_Updated_At               datetime2(6)        NOT NULL
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
    SET @Run_Deletes = @My_Inserts  

END

GO
