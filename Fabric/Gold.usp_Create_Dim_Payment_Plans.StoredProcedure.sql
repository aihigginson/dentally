--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Dim_Payment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Dim_Payment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Payment_Plans]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Payment_Plans]
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


    DROP TABLE IF EXISTS Gold.Dim_Payment_Plans;

    CREATE TABLE Gold.Dim_Payment_Plans (
        pk_Payment_Plan        BIGINT          NOT NULL,
        Tenant_ID                      INT             NOT NULL,
        Payment_Plan_ID        INT             NOT NULL,
        Payment_Plan_Name      VARCHAR(255)   NULL,
        Patient_Friendly_Name  VARCHAR(255)   NULL,
        Active                 BIT             NULL,
        Colour                 VARCHAR(20)    NULL,
        Site_ID                VARCHAR(50)    NULL,
        Dentist_Recall_Interval_Months   INT   NULL,
        Hygienist_Recall_Interval_Months INT   NULL,
        Emergency_Duration_Mins          INT   NULL,
        Exam_Duration_Mins               INT   NULL,
        Exam_Scale_Polish_Duration_Mins  INT   NULL,
        Scale_Polish_Duration_Mins       INT   NULL,
        Created_Date           datetime2(3) NULL,
        DW_Created_At          datetime2(6)    NOT NULL,
        DW_Updated_At          datetime2(6)    NOT NULL
    );

        -- Insert -1 unknown/shared seed row
        INSERT INTO Gold.Dim_Payment_Plans (pk_Payment_Plan, Tenant_ID, Payment_Plan_ID, DW_Created_At, DW_Updated_At)
        VALUES (-1, -1, -1, SYSUTCDATETIME(), SYSUTCDATETIME());

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
