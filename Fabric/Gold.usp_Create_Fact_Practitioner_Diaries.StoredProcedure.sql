--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Fact_Practitioner_Diaries
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Fact_Practitioner_Diaries @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
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
        pk_Practitioner_Diary        BIGINT            NOT NULL IDENTITY,
        Tenant_ID                      INT             NOT NULL,
        bk_Practitioner_Diary_ID     VARCHAR(50)      NOT NULL,   -- Natural key

        fk_Practitioner              BIGINT            NULL,
        fk_Date_Day                  BIGINT            NULL,

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
