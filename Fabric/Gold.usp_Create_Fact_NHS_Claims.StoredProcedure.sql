--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Fact_NHS_Claims
--  Author           :  AIH
--  Initital Date    :  03/06/2026
--  History          :
--    *01     03/06/2026  AIH Initial Release
--  To Run           :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Create_Fact_NHS_Claims @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_NHS_Claims]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_NHS_Claims]
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

    DROP TABLE IF EXISTS Gold.Fact_NHS_Claims;

    CREATE TABLE Gold.Fact_NHS_Claims (
        pk_NHS_Claim                BIGINT              NOT NULL IDENTITY,
        Tenant_ID                   INT                 NOT NULL,
        bk_NHS_Claim_ID             VARCHAR(50)         NOT NULL,

        fk_Patient                  BIGINT              NULL,
        fk_Practitioner             BIGINT              NULL,
        fk_Treatment_Plan           BIGINT              NULL,
        fk_Practice_Site            BIGINT              NULL,
        fk_NHS_Contract             BIGINT              NULL,

        fk_Date_Submitted           BIGINT              NULL,
        fk_Date_Approval            BIGINT              NULL,

        Claim_Status                VARCHAR(50)         NULL,
        Sequence_Number             INT                 NULL,
        UDA_Band                    VARCHAR(10)         NULL,
        Ortho                       BIT                 NULL,
        Continuation_Part_Number    INT                 NULL,
        Status_Comments             VARCHAR(MAX)        NULL,

        Expected_UDA                DECIMAL(18,4)       NULL,
        Awarded_UDA                 DECIMAL(18,4)       NULL,
        Patient_Charge              DECIMAL(18,4)       NULL,
        Dentist_Charge              DECIMAL(18,4)       NULL,
        Awarded_Dentist_Charge      DECIMAL(18,4)       NULL,
        NI_Calculated_Dentist_Fee   DECIMAL(18,4)       NULL,
        NI_Calculated_Patient_Fee   DECIMAL(18,4)       NULL,
        SCOT_Amount_Authorised      DECIMAL(18,4)       NULL,
        SCOT_Amount_Expected        DECIMAL(18,4)       NULL,

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
