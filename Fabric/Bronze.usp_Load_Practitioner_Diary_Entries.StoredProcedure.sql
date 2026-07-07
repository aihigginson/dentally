--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Practitioner_Diary_Entries
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     20/05/2026  AIH Fix Stage field names: date (not day); default Unavailable=0 (field not in API)
--    *04     07/07/2026  AIH Day = COALESCE(day, date): REAL Dentally rota field is `day` (mock used
--                            `date`). Reading only `date` left Day NULL for real -> Fact_Practitioner_Diaries
--                            Day_Date/fk_Date_Day NULL -> Worked_Hours NULL -> Chair Util / Rev-per-Clinical-Hour
--                            / Days-Until-Free all blank. COALESCE handles real (day) + mock (date).
--    *05     07/07/2026  AIH Unavailable = real `unavailable` flag (was hardcoded 0 "field not in API" --
--                            true for mock, FALSE for real). Hardcoded 0 counted holiday/blocked days as
--                            available clinical capacity -> inflated working hours. Silver already inverts
--                            Unavailable->Available and Fact gates Available_Clinical_Mins on it.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Practitioner_Diary_Entries @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Practitioner_Diary_Entries]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Practitioner_Diary_Entries]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id     AS INT)   AS Tenant_ID
            , LEFT(id,                 255)    AS ID
            , TRY_CAST(practitioner_id AS INT) AS Practitioner_ID
            , LEFT(COALESCE([day], [date]), 255) AS Day
            , LEFT(start_time,         255)    AS Start_Time
            , LEFT(end_time,           255)    AS End_Time
            -- REAL Dentally rota carries `unavailable` (bool). Mock did not, so this was hardcoded
            -- 0 -> every entry looked available (incl. holiday/blocked days that still carry the
            -- practitioner's normal hours) -> Silver.Available always 1 -> Fact counted them as
            -- Available_Clinical_Mins -> working hours inflated / chair utilisation deflated. Read
            -- it now; CAST covers bit ('1'/'0') OR string ('true'/'false'); NULL/absent -> available.
            , CASE WHEN LOWER(LTRIM(RTRIM(CAST([unavailable] AS VARCHAR(10))))) IN ('true', '1')
                   THEN CAST(1.0 AS DECIMAL(18,4)) ELSE CAST(0.0 AS DECIMAL(18,4)) END AS Unavailable
        INTO #src
        FROM Stage.Practitioner_Diary_Entries
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Practitioner_ID = src.Practitioner_ID
            , tgt.Day             = src.Day
            , tgt.Start_Time      = src.Start_Time
            , tgt.End_Time        = src.End_Time
            , tgt.Unavailable     = src.Unavailable
            , tgt.DW_Loaded_At    = SYSUTCDATETIME()
        FROM Bronze.Practitioner_Diary AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Practitioner_Diary (Tenant_ID, ID, Practitioner_ID, Day, Start_Time, End_Time, Unavailable, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Practitioner_ID, src.Day, src.Start_Time, src.End_Time, src.Unavailable, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Practitioner_Diary tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Practitioner_Diary AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
