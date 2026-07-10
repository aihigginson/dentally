--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Treatment_Categories
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Treatment_Categories]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Treatment_Categories]
(
      @Tenant_ID    INT
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
              TRY_CAST(tenant_id AS INT)                          AS Tenant_ID
            , TRY_CAST(id AS DECIMAL(18,4))                       AS ID
            , LEFT(name, 255)                                     AS Name
        INTO #src
        FROM Stage.Treatment_Categories
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Name         = src.Name
            , tgt.DW_Loaded_At = SYSUTCDATETIME()
        FROM Bronze.Treatment_Categories AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Treatment_Categories (Tenant_ID, ID, Name, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Name, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Treatment_Categories tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;


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
