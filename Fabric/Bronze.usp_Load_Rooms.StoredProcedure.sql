--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Rooms
--  Author           :  AIH
--  Initital Date    :  19/05/2026
--  History          :
--    *01     19/05/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Rooms]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Rooms]
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
              TRY_CAST(tenant_id        AS INT)                        AS Tenant_ID
            , LEFT(id,                     255)                        AS ID
            , LEFT(name,                   255)                        AS Name
            , LEFT(site_id,                255)                        AS Site_ID
            , LEFT(colour,                 255)                        AS Colour
            , TRY_CAST(calendar_position   AS DECIMAL(18,4))           AS Calendar_Position
            , LEFT(created_at,             255)                        AS Created_At
            , LEFT(updated_at,             255)                        AS Updated_At
            , LEFT(practice_id,            255)                        AS Practice_ID
        INTO #src
        FROM Stage.Rooms
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Name              = src.Name
            , tgt.Site_ID           = src.Site_ID
            , tgt.Colour            = src.Colour
            , tgt.Calendar_Position = src.Calendar_Position
            , tgt.Created_At        = src.Created_At
            , tgt.Updated_At        = src.Updated_At
            , tgt.Practice_ID       = src.Practice_ID
            , tgt.DW_Loaded_At      = SYSUTCDATETIME()
        FROM Bronze.Rooms AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Rooms (Tenant_ID, ID, Name, Site_ID, Colour, Calendar_Position, Created_At, Updated_At, Practice_ID, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Name, src.Site_ID, src.Colour, src.Calendar_Position, src.Created_At, src.Updated_At, src.Practice_ID, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Rooms tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Rooms AS tgt
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
