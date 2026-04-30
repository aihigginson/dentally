--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Dim_Treatments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Dim_Treatments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
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
        pk_Treatment              BIGINT            NOT NULL IDENTITY,
        Tenant_ID                      INT             NOT NULL,
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
