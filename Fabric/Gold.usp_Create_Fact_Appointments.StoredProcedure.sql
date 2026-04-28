/****** Object:  StoredProcedure [Gold].[usp_Create_Fact_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Fact_Appointments
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Appointments]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Appointments]
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

    DROP TABLE IF EXISTS Gold.Fact_Appointments;
    CREATE TABLE Gold.Fact_Appointments (
        pk_Appointment              INT                 NOT NULL IDENTITY,
        bk_Appointment_ID           INT                 NOT NULL,   -- Natural key

        fk_Patient                  INT                 NULL,
        fk_Practitioner             INT                 NULL,
        fk_Payment_Plan             INT                 NULL,
        fk_Practice_Site            INT                 NULL,
        fk_User                     INT                 NULL,

        fk_Date_Start               INT                 NULL,
        fk_Date_Pending             INT                 NULL,
        fk_Date_Created             INT                 NULL,

        Room_ID                     VARCHAR(50)        NULL,
        State                       VARCHAR(50)        NULL,
        Reason                      VARCHAR(100)       NULL,
        Treatment_Description       VARCHAR(MAX)       NULL,
        Notes                       VARCHAR(MAX)       NULL,
        Cancellation_Reason_ID      VARCHAR(50)        NULL,

        Arrived_At                  datetime2(3)   NULL,
        In_Surgery_At               datetime2(3)   NULL,
        Completed_At                datetime2(3)   NULL,
        Confirmed_At                datetime2(3)   NULL,
        Cancelled_At                datetime2(3)   NULL,
        Did_Not_Attend_At           datetime2(3)   NULL,
        Start_Time                  datetime2(3)   NULL,
        Finish_Time                 datetime2(3)   NULL,
        Pending_At                  datetime2(3)   NULL,

        Is_Completed                BIT                 NULL,
        Is_Cancelled                BIT                 NULL,
        Is_DNA                      BIT                 NULL,
        Is_Arrived                  BIT                 NULL,

        Duration_Mins               INT                 NULL,
        Waiting_Mins                INT                 NULL,
        In_Surgery_Mins             INT                 NULL,

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
