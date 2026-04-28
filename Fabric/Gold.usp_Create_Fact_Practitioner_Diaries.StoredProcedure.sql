/****** Object:  StoredProcedure [Gold].[usp_Create_Fact_Practitioner_Diaries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Fact_Practitioner_Diaries
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Practitioner_Diaries]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Practitioner_Diaries]
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

    DROP TABLE IF EXISTS Gold.Fact_Practitioner_Diaries;
    CREATE TABLE Gold.Fact_Practitioner_Diaries (
        pk_Practitioner_Diary        INT               NOT NULL IDENTITY,
        bk_Practitioner_Diary_ID     VARCHAR(50)      NOT NULL,   -- Natural key

        fk_Practitioner              INT               NULL,
        fk_Date_Day                  INT               NULL,

        Day_Date                     DATE              NULL,
        Start_Time                   TIME              NULL,
        End_Time                     TIME              NULL,
        Unavailable                  BIT               NULL,

        Session_Duration_Mins        INT               NULL,
        Total_Break_Mins             INT               NULL,
        Available_Clinical_Mins      INT               NULL,
        Break_Count                  INT               NULL,

        DW_Created_At                datetime2(6)      NOT NULL,
        DW_Updated_At                datetime2(6)      NOT NULL
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
