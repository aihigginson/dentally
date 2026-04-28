/****** Object:  StoredProcedure [Gold].[usp_Create_Fact_Treatment_Plan_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
------------------------------------------------------------
-- Gold.usp_Create_Fact_Treatment_Plan_Items
------------------------------------------------------------
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
        pk_Treatment_Plan_Item      INT                 NOT NULL IDENTITY,
        bk_Treatment_Plan_Item_ID   VARCHAR(50)        NOT NULL,   -- Natural key

        fk_Treatment_Plan           INT                 NULL,
        fk_Patient                  INT                 NULL,
        fk_Practitioner             INT                 NULL,
        fk_Payment_Plan             INT                 NULL,
        fk_Treatment                INT                 NULL,

        fk_Date_Created             INT                 NULL,
        fk_Date_Completed           INT                 NULL,
        fk_Date_Updated             INT                 NULL,

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
