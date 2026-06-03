--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Dim_NHS_Contracts
--  Author           :  AIH
--  Initital Date    :  03/06/2026
--  History          :
--    *01     03/06/2026  AIH Initial Release
--  To Run           :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Create_Dim_NHS_Contracts @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_NHS_Contracts]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_NHS_Contracts]
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

    DROP TABLE IF EXISTS Gold.Dim_NHS_Contracts;

    CREATE TABLE Gold.Dim_NHS_Contracts (
        pk_NHS_Contract             BIGINT              NOT NULL,
        Tenant_ID                   INT                 NOT NULL,
        bk_Contract_ID              VARCHAR(50)         NOT NULL,
        Contract_Number             VARCHAR(50)         NULL,
        Contract_Name               VARCHAR(255)        NULL,
        Site_ID                     VARCHAR(50)         NULL,
        Active                      BIT                 NULL,
        PDS_Plus                    BIT                 NULL,
        NHS_Location_ID             VARCHAR(50)         NULL,
        NHS_Site_ID                 VARCHAR(50)         NULL,
        Start_Date                  DATE                NULL,
        End_Date                    DATE                NULL,
        UDA_Target                  DECIMAL(18,4)       NULL,
        UDA_Value                   DECIMAL(18,4)       NULL,
        UOA_Target                  DECIMAL(18,4)       NULL,
        UOA_Value                   DECIMAL(18,4)       NULL,
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
    SET @Run_Deletes = @My_Deletes

END
GO
