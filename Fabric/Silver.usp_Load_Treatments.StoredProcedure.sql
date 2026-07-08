--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Treatments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Treatments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     19/05/2026  AIH Read Active from Bronze (now populated); simplify Code/ID reads (Bronze now typed)
--    *03     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *04     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Treatments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Treatments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Treatments]
GO
CREATE PROCEDURE [Silver].[usp_Load_Treatments]
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
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        SELECT
            staged.*,
            CONVERT(VARBINARY(32), HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
        ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Code] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nomenclature] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Region] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[UDA_Band] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Category_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                ID  AS [Id],
                NULL  AS [Site_ID],
                -- Site_ID not in Bronze.Treatments
        LEFT(Code, 50)  AS [Code],
                NULL  AS [Name],
                NULL  AS [Type],
                -- Type not in Bronze
        CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Active],
                LEFT(Nomenclature,         255)  AS [Nomenclature],
                LEFT(Region,               255)  AS [Region],
                TRY_CAST(UDA_Band           AS decimal(10,2))  AS [UDA_Band],
                TRY_CAST(NHS_Treatment_Cat  AS decimal(10,2))  AS [NHS_Treatment_Cat],
                TRY_CAST(ROUND(TRY_CAST(Treatment_Category_ID AS float),0) AS int)  AS [Treatment_Category_ID],
                LEFT(Created_At, 20)  AS [Created_At],
                LEFT(Updated_At, 20)  AS [Updated_At]
            FROM Bronze.Treatments
            WHERE ID IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Site_ID] = src.[Site_ID],
            [Code] = src.[Code],
            [Name] = src.[Name],
            [Type] = src.[Type],
            [Active] = src.[Active],
            [Nomenclature] = src.[Nomenclature],
            [Region] = src.[Region],
            [UDA_Band] = src.[UDA_Band],
            [NHS_Treatment_Cat] = src.[NHS_Treatment_Cat],
            [Treatment_Category_ID] = src.[Treatment_Category_ID],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Treatments] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Treatments] ([Tenant_ID], [Id], [Site_ID], [Code], [Name], [Type], [Active], [Nomenclature], [Region], [UDA_Band], [NHS_Treatment_Cat], [Treatment_Category_ID], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Id], src.[Site_ID], src.[Code], src.[Name], src.[Type], src.[Active], src.[Nomenclature], src.[Region], src.[UDA_Band], src.[NHS_Treatment_Cat], src.[Treatment_Category_ID], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Treatments] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Treatments] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Id] = tgt.[Id]
        );
        SET @My_Deletes = @@ROWCOUNT;

        DROP TABLE IF EXISTS #src;

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************

    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes

END
GO
