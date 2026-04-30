--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Practitioner_Diary_Breaks
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Practitioner_Diary_Breaks]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Practitioner_Diary_Breaks]
(
      @Tenant_ID    INT
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
    , @Full_Refresh BIT    = 0
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                          AS Tenant_ID
            , LEFT(practitioner_diary_id, 255)                    AS Practitioner_Diary_ID
            , LEFT(break_name, 255)                               AS Break_Name
            , LEFT(start_time, 255)                               AS Start_Time
            , LEFT(end_time, 255)                                  AS End_Time
        INTO #src
        FROM Stage.Practitioner_Diary_Breaks
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Start_Time   = src.Start_Time
            , tgt.End_Time     = src.End_Time
            , tgt.DW_Loaded_At = SYSUTCDATETIME()
        FROM Bronze.Practitioner_Diary_Breaks AS tgt
        INNER JOIN #src AS src
            ON tgt.Tenant_ID              = src.Tenant_ID
           AND tgt.Practitioner_Diary_ID  = src.Practitioner_Diary_ID
           AND tgt.Break_Name             = src.Break_Name;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Practitioner_Diary_Breaks (Tenant_ID, Practitioner_Diary_ID, Break_Name, Start_Time, End_Time, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Practitioner_Diary_ID, src.Break_Name, src.Start_Time, src.End_Time, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM Bronze.Practitioner_Diary_Breaks tgt
            WHERE tgt.Tenant_ID = src.Tenant_ID
              AND tgt.Practitioner_Diary_ID = src.Practitioner_Diary_ID
              AND tgt.Break_Name = src.Break_Name
        );
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Practitioner_Diary_Breaks AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (
                SELECT 1 FROM #src
                WHERE Practitioner_Diary_ID = tgt.Practitioner_Diary_ID
                  AND Break_Name = tgt.Break_Name
              );
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH THROW; END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
