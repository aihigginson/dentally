/****** Object:  StoredProcedure [Gold].[usp_Create_Fact_Invoice_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Fact_Invoice_Items
------------------------------------------------------------
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
        pk_Invoice_Item             INT                 NOT NULL IDENTITY,
        bk_Invoice_Item_ID          VARCHAR(50)        NOT NULL,   -- Natural key

        fk_Patient                  INT                 NULL,
        fk_Practitioner             INT                 NULL,
        fk_Payment_Plan             INT                 NULL,
        fk_Treatment_Plan           INT                 NULL,
        fk_Account                  INT                 NULL,
        fk_Practice_Site            INT                 NULL,
        fk_User                     INT                 NULL,

        fk_Date_Invoice             INT                 NULL,
        fk_Date_Due                 INT                 NULL,
        fk_Date_Paid                INT                 NULL,
        fk_Date_Created             INT                 NULL,

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
