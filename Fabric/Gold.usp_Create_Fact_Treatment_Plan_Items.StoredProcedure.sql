--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Fact_Treatment_Plan_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Fact_Treatment_Plan_Items @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Treatment_Plan_Items]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Treatment_Plan_Items]
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

    DROP TABLE IF EXISTS Gold.Fact_Treatment_Plan_Items;
    CREATE TABLE Gold.Fact_Treatment_Plan_Items (
        pk_Treatment_Plan_Item      BIGINT              NOT NULL IDENTITY,
        Tenant_ID                      INT             NOT NULL,
        bk_Treatment_Plan_Item_ID   VARCHAR(50)        NOT NULL,   -- Natural key

        fk_Treatment_Plan           BIGINT              NULL,
        fk_Patient                  BIGINT              NULL,
        fk_Practitioner             BIGINT              NULL,
        fk_Payment_Plan             BIGINT              NULL,
        fk_Treatment                BIGINT              NULL,

        fk_Date_Created             BIGINT              NULL,
        fk_Date_Completed           BIGINT              NULL,
        fk_Date_Updated             BIGINT              NULL,

        Treatment_Plan_ID           INT                 NULL,
        Invoice_ID                  INT                 NULL,
        Treatment_Appointment_ID    VARCHAR(50)        NULL,
        Referrer_ID                 INT                 NULL,

        Nomenclature                VARCHAR(255)       NULL,
        Patient_Nomenclature        VARCHAR(255)       NULL,
        NHS_Treatment_Cat           VARCHAR(50)        NULL,
        UDA_Band                    VARCHAR(50)        NULL,
        Region                      VARCHAR(100)       NULL,
        Notes                       VARCHAR(MAX)       NULL,
        Position                    INT                 NULL,
        Base_Chart                  BIT                 NULL,

        Completed                   BIT                 NULL,
        Charged                     BIT                 NULL,
        Appear_On_Invoice           BIT                 NULL,

        Price                       DECIMAL(18,4)       NULL,
        Duration_Mins               INT                 NULL,

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
