--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Treatments] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Treatments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Treatments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Treatments]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Treatments]
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

        -- Mock: id, name, code, chart_type
        -- Bronze: ID, Nomenclature, Code — map name→Nomenclature, code→Code (as VARCHAR)
        SELECT
              TRY_CAST(tenant_id AS INT)   AS Tenant_ID
            , TRY_CAST(id        AS INT)   AS ID
            , LEFT(name,   255)            AS Nomenclature
            , LEFT(code,   255)            AS Code
        INTO #src
        FROM Stage.Treatments
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Nomenclature  = src.Nomenclature
            , tgt.Code          = src.Code
            , tgt.DW_Loaded_At  = SYSUTCDATETIME()
        FROM Bronze.Treatments AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND TRY_CAST(tgt.ID AS INT) = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Treatments (Tenant_ID, ID, Nomenclature, Code, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Nomenclature, src.Code, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Treatments tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND TRY_CAST(tgt.ID AS INT) = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Treatments AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = TRY_CAST(tgt.ID AS INT));
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
