/****** Object:  StoredProcedure [Gold].[usp_Create_Fact_Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Fact_Recalls
------------------------------------------------------------
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
        pk_Recall                   INT               NOT NULL IDENTITY,
        bk_Recall_ID                VARCHAR(50)      NOT NULL,   -- Natural key

        fk_Patient                  INT               NULL,

        fk_Date_Due                 INT               NULL,
        fk_Date_Run                 INT               NULL,
        fk_Date_First_Reminder      INT               NULL,
        fk_Date_Second_Reminder     INT               NULL,
        fk_Date_Last_Reminded       INT               NULL,

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
