/****** Object:  StoredProcedure [Gold].[usp_Create_Dim_Treatments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Dim_Treatments
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Treatments]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Treatments]
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

    DROP TABLE IF EXISTS Gold.Dim_Treatments;

    CREATE TABLE Gold.Dim_Treatments (
        pk_Treatment              INT               NOT NULL IDENTITY,
        Treatment_ID              INT               NOT NULL,
        Treatment_Code            VARCHAR(50)      NULL,
        Nomenclature              VARCHAR(255)     NULL,
        Patient_Nomenclature      VARCHAR(255)     NULL,
        Description               VARCHAR(MAX)     NULL,
        Patient_Description       VARCHAR(255)     NULL,
        Notes                     VARCHAR(255)     NULL,
        Region                    VARCHAR(100)     NULL,
        UDA_Band                  INT               NULL,
        NHS_Treatment_Cat         INT               NULL,
        Treatment_Category_ID     INT               NULL,
        Treatment_Category_Name   VARCHAR(255)     NULL,
        Created_Date              datetime2(3) NULL,
        Updated_Date              datetime2(3) NULL,
        DW_Created_At             datetime2(6)      NOT NULL,
        DW_Updated_At             datetime2(6)      NOT NULL
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
