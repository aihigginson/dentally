--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Treatments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
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
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Code] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Description] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nomenclature] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Nomenclature] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Description] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Notes] AS VARCHAR(500)), ''),
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
                TRY_CAST(ROUND(CAST(ID AS float),0) AS int)  AS [Id],
                NULL  AS [Site_Id],
                -- Site_Id not in Bronze.Treatments
        LEFT(CAST(TRY_CAST(ROUND(CAST(Code AS float),0) AS bigint) AS VARCHAR(50)), 50)  AS [Code],
                NULL  AS [Name],
                -- Name not in Bronze (Description used below)
        LEFT(Description, 255)  AS [Description],
                NULL  AS [Type],
                -- Type not in Bronze
        CAST(NULL AS bit)  AS [Active],
                -- Active not in Bronze
        LEFT(Nomenclature,         255)  AS [Nomenclature],
                LEFT(Patient_Nomenclature, 255)  AS [Patient_Nomenclature],
                LEFT(Patient_Description,  255)  AS [Patient_Description],
                LEFT(Notes,                255)  AS [Notes],
                LEFT(Region,               255)  AS [Region],
                TRY_CAST(UDA_Band           AS decimal(10,2))  AS [UDA_Band],
                TRY_CAST(NHS_Treatment_Cat  AS decimal(10,2))  AS [NHS_Treatment_Cat],
                TRY_CAST(ROUND(CAST(Treatment_Category_ID AS float),0) AS int)  AS [Treatment_Category_ID],
                LEFT(Created_At, 20)  AS [Created_At],
                LEFT(Updated_At, 20)  AS [Updated_At]
            FROM Bronze.Treatments
            WHERE TRY_CAST(ROUND(CAST(ID AS float),0) AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Site_Id] = src.[Site_Id],
            [Code] = src.[Code],
            [Name] = src.[Name],
            [Description] = src.[Description],
            [Type] = src.[Type],
            [Active] = src.[Active],
            [Nomenclature] = src.[Nomenclature],
            [Patient_Nomenclature] = src.[Patient_Nomenclature],
            [Patient_Description] = src.[Patient_Description],
            [Notes] = src.[Notes],
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

        INSERT INTO [Silver].[Treatments] ([Tenant_ID], [Id], [Site_Id], [Code], [Name], [Description], [Type], [Active], [Nomenclature], [Patient_Nomenclature], [Patient_Description], [Notes], [Region], [UDA_Band], [NHS_Treatment_Cat], [Treatment_Category_ID], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Id], src.[Site_Id], src.[Code], src.[Name], src.[Description], src.[Type], src.[Active], src.[Nomenclature], src.[Patient_Nomenclature], src.[Patient_Description], src.[Notes], src.[Region], src.[UDA_Band], src.[NHS_Treatment_Cat], src.[Treatment_Category_ID], src.[Created_At], src.[Updated_At],
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
