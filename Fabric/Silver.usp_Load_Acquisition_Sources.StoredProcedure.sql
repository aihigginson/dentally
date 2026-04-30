--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Acquisition_Sources
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Acquisition_Sources @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Acquisition_Sources]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Acquisition_Sources]
GO
CREATE PROCEDURE [Silver].[usp_Load_Acquisition_Sources]
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
        ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Notes] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                -- Bronze ID is VARCHAR(255); Silver is VARCHAR(50) – truncate safely
        LEFT(CAST(ID AS VARCHAR(255)), 50)  AS [Acquisition_Source_Id],
                -- Bronze Active is int; Silver is bit
        CASE WHEN Active = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Active],
                Name  AS [Name],
                -- Bronze Notes is VARCHAR(max); Silver is VARCHAR(1000)
        LEFT(Notes, 1000)  AS [Notes]
            FROM Bronze.Acquisition_Sources
        ) AS staged;

        UPDATE tgt
        SET
            [Active] = src.[Active],
            [Name] = src.[Name],
            [Notes] = src.[Notes],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Acquisition_Sources] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Acquisition_Source_Id] = src.[Acquisition_Source_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Acquisition_Sources] ([Tenant_ID], [Acquisition_Source_Id], [Active], [Name], [Notes],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Acquisition_Source_Id], src.[Active], src.[Name], src.[Notes],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Acquisition_Sources] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Acquisition_Source_Id] = src.[Acquisition_Source_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Acquisition_Sources] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Acquisition_Source_Id] = tgt.[Acquisition_Source_Id]
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
