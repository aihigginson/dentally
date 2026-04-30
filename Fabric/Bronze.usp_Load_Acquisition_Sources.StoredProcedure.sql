--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Acquisition_Sources
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Acquisition_Sources]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Acquisition_Sources]
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
              TRY_CAST(tenant_id AS INT)                                                                    AS Tenant_ID
            , LEFT(id, 255)                                                                                 AS ID
            , CASE WHEN active IN ('True', '1', 'true') THEN 1 ELSE 0 END                                  AS Active
            , LEFT(name, 255)                                                                               AS Name
            , CAST(notes AS VARCHAR(MAX))                                                                   AS Notes
        INTO #src
        FROM Stage.Acquisition_Sources
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Active       = src.Active
            , tgt.Name         = src.Name
            , tgt.Notes        = src.Notes
            , tgt.DW_Loaded_At = SYSUTCDATETIME()
        FROM Bronze.Acquisition_Sources AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Acquisition_Sources (Tenant_ID, ID, Active, Name, Notes, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Active, src.Name, src.Notes, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Acquisition_Sources tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Acquisition_Sources AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
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
