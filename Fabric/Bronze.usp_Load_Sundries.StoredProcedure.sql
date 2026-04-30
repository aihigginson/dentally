--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Sundries
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Sundries]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Sundries]
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
            , LEFT(id, 255)                                       AS ID
            , LEFT(name, 255)                                     AS Name
            , LEFT(nickname, 255)                                 AS Nickname
            , TRY_CAST(price AS DECIMAL(18,4))                    AS Price
            , LEFT(site_id, 255)                                  AS Site_ID
        INTO #src
        FROM Stage.Sundries
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Name         = src.Name
            , tgt.Nickname     = src.Nickname
            , tgt.Price        = src.Price
            , tgt.Site_ID      = src.Site_ID
            , tgt.DW_Loaded_At = SYSUTCDATETIME()
        FROM Bronze.Sundries AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Sundries (Tenant_ID, ID, Name, Nickname, Price, Site_ID, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Name, src.Nickname, src.Price, src.Site_ID, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Sundries tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Sundries AS tgt
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
