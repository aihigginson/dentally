--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Fact_Recalls
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Fact_Recalls @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Recalls]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Recalls]
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

    DROP TABLE IF EXISTS Gold.Fact_Recalls;

    CREATE TABLE Gold.Fact_Recalls (
        pk_Recall                   BIGINT            NOT NULL IDENTITY,
        Tenant_ID                      INT             NOT NULL,
        bk_Recall_ID                VARCHAR(50)      NOT NULL,   -- Natural key

        fk_Patient                  BIGINT            NULL,

        fk_Date_Due                 BIGINT            NULL,
        fk_Date_Run                 BIGINT            NULL,
        fk_Date_First_Reminder      BIGINT            NULL,
        fk_Date_Second_Reminder     BIGINT            NULL,
        fk_Date_Last_Reminded       BIGINT            NULL,

        Appointment_ID              VARCHAR(50)      NULL,

        Recall_Type                 VARCHAR(100)     NULL,
        Recall_Method               VARCHAR(100)     NULL,
        Status                      VARCHAR(100)     NULL,
        Workflow_Status             VARCHAR(100)     NULL,
        Workflow_Stage_ID           VARCHAR(50)      NULL,
        First_Reminder_Type         VARCHAR(100)     NULL,
        Second_Reminder_Type        VARCHAR(100)     NULL,
        Latest_Reminder_Type        VARCHAR(100)     NULL,

        Times_Contacted             INT               NULL,
        Due_Date                    DATE              NULL,
        Run_Date                    DATE              NULL,

        Days_Overdue                INT               NULL,

        DW_Created_At               datetime2(6)      NOT NULL,
        DW_Updated_At               datetime2(6)      NOT NULL
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
