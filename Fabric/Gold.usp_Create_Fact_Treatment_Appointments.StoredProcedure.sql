/****** Object:  StoredProcedure [Gold].[usp_Create_Fact_Treatment_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Fact_Treatment_Appointments
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Treatment_Appointments]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Treatment_Appointments]
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

    DROP TABLE IF EXISTS Gold.Fact_Treatment_Appointments;
    CREATE TABLE Gold.Fact_Treatment_Appointments (
        pk_Treatment_Appointment     INT                 NOT NULL IDENTITY,
        bk_Treatment_Appointment_ID  VARCHAR(50)        NOT NULL,   -- Natural key

        fk_Patient                   INT                 NULL,
        fk_Treatment_Plan            INT                 NULL,

        fk_Date_Appointment          INT                 NULL,
        fk_Date_Created              INT                 NULL,

        Appointment_ID               INT                 NULL,
        Treatment_Plan_ID            INT                 NULL,

        Position                     INT                 NULL,
        Bookable                     BIT                 NULL,
        Notes                        VARCHAR(MAX)       NULL,
        Created_At                   datetime2(3)   NULL,
        Updated_At                   datetime2(3)   NULL,

        DW_Created_At                datetime2(6)        NOT NULL,
        DW_Updated_At                datetime2(6)        NOT NULL
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
