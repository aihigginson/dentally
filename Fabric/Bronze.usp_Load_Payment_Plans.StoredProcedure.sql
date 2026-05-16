--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Payment_Plans] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Payment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Payment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Payment_Plans]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Payment_Plans]
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
              TRY_CAST(tenant_id               AS INT)            AS Tenant_ID
            , TRY_CAST(id                      AS INT)            AS Payment_Plan_ID
            , LEFT(name,                          255)            AS Payment_Plan_Name
            , TRY_CAST(dentist_recall_interval  AS DECIMAL(18,4)) AS Dentist_Recall_Interval
            , TRY_CAST(hygienist_recall_interval AS DECIMAL(18,4)) AS Hygienist_Recall_Interval
            , TRY_CAST(exam_duration            AS DECIMAL(18,4)) AS Exam_Duration
            , TRY_CAST(scale_polish_duration    AS DECIMAL(18,4)) AS Scale_And_Polish_Duration
        INTO #src
        FROM Stage.Payment_Plans
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Payment_Plan_Name          = src.Payment_Plan_Name
            , tgt.Dentist_Recall_Interval    = src.Dentist_Recall_Interval
            , tgt.Hygienist_Recall_Interval  = src.Hygienist_Recall_Interval
            , tgt.Exam_Duration              = src.Exam_Duration
            , tgt.Scale_And_Polish_Duration  = src.Scale_And_Polish_Duration
            , tgt.DW_Loaded_At               = SYSUTCDATETIME()
        FROM Bronze.Payment_Plans AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Payment_Plan_ID = src.Payment_Plan_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Payment_Plans (Tenant_ID, Payment_Plan_ID, Payment_Plan_Name, Dentist_Recall_Interval, Hygienist_Recall_Interval, Exam_Duration, Scale_And_Polish_Duration, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Payment_Plan_ID, src.Payment_Plan_Name, src.Dentist_Recall_Interval, src.Hygienist_Recall_Interval, src.Exam_Duration, src.Scale_And_Polish_Duration, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Payment_Plans tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Payment_Plan_ID = src.Payment_Plan_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Payment_Plans AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Payment_Plan_ID = tgt.Payment_Plan_ID);
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
