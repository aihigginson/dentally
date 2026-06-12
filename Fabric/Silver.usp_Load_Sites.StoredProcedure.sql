--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Sites] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Sites
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     19/05/2026  AIH Add Nickname from Bronze; simplify Nickname read (now VARCHAR in Bronze)
--    *03     20/05/2026  AIH Column naming convention fixes (ID/_ID, lowercase cols -> Pascal_Case, day abbreviations)
--    *04     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Sites @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Sites]
GO
CREATE PROCEDURE [Silver].[usp_Load_Sites]
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
        ISNULL(CAST(staged.[Practice_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nickname] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Address_Line_1] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Address_Line_2] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Town] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Postcode] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Phone_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Website] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Logo_URL] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Default_Payment_Plan_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Monday_Open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Monday_Close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Tuesday_Open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Tuesday_Close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Wednesday_Open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Wednesday_Close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Thursday_Open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Thursday_Close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Friday_Open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Friday_Close] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(Site_ID,       50)  AS [Site_ID],
                LEFT(Practice_ID,   50)  AS [Practice_ID],
                Name  AS [Name],
                LEFT(Nickname, 255)  AS [Nickname],
                CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN 1 ELSE 0 END  AS [Active],
                Address_Line_1  AS [Address_Line_1],
                Address_Line_2  AS [Address_Line_2],
                Town  AS [Town],
                Postcode  AS [Postcode],
                Phone_Number  AS [Phone_Number],
                Website  AS [Website],
                Logo_Url  AS [Logo_URL],
                -- Bronze Default_Payment_Plan_ID is decimal(18,4); Silver is VARCHAR(255)
        LEFT(CAST(TRY_CAST(ROUND(CAST(Default_Payment_Plan_ID AS float),0) AS bigint) AS VARCHAR(255)), 255)  AS [Default_Payment_Plan_ID],
                Monday_Open  AS [Monday_Open],
                Monday_Close  AS [Monday_Close],
                Tuesday_Open  AS [Tuesday_Open],
                Tuesday_Close  AS [Tuesday_Close],
                Wednesday_Open  AS [Wednesday_Open],
                Wednesday_Close  AS [Wednesday_Close],
                Thursday_Open  AS [Thursday_Open],
                Thursday_Close  AS [Thursday_Close],
                Friday_Open  AS [Friday_Open],
                Friday_Close  AS [Friday_Close]
            FROM Bronze.Sites
        ) AS staged;

        UPDATE tgt
        SET
            [Practice_ID] = src.[Practice_ID],
            [Name] = src.[Name],
            [Nickname] = src.[Nickname],
            [Active] = src.[Active],
            [Address_Line_1] = src.[Address_Line_1],
            [Address_Line_2] = src.[Address_Line_2],
            [Town] = src.[Town],
            [Postcode] = src.[Postcode],
            [Phone_Number] = src.[Phone_Number],
            [Website] = src.[Website],
            [Logo_URL] = src.[Logo_URL],
            [Default_Payment_Plan_ID] = src.[Default_Payment_Plan_ID],
            [Monday_Open] = src.[Monday_Open],
            [Monday_Close] = src.[Monday_Close],
            [Tuesday_Open] = src.[Tuesday_Open],
            [Tuesday_Close] = src.[Tuesday_Close],
            [Wednesday_Open] = src.[Wednesday_Open],
            [Wednesday_Close] = src.[Wednesday_Close],
            [Thursday_Open] = src.[Thursday_Open],
            [Thursday_Close] = src.[Thursday_Close],
            [Friday_Open] = src.[Friday_Open],
            [Friday_Close] = src.[Friday_Close],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Sites] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Site_ID] = src.[Site_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Sites] ([Tenant_ID], [Site_ID], [Practice_ID], [Name], [Nickname], [Active], [Address_Line_1], [Address_Line_2], [Town], [Postcode], [Phone_Number], [Website], [Logo_URL], [Default_Payment_Plan_ID], [Monday_Open], [Monday_Close], [Tuesday_Open], [Tuesday_Close], [Wednesday_Open], [Wednesday_Close], [Thursday_Open], [Thursday_Close], [Friday_Open], [Friday_Close], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Site_ID], src.[Practice_ID], src.[Name], src.[Nickname], src.[Active], src.[Address_Line_1], src.[Address_Line_2], src.[Town], src.[Postcode], src.[Phone_Number], src.[Website], src.[Logo_URL], src.[Default_Payment_Plan_ID], src.[Monday_Open], src.[Monday_Close], src.[Tuesday_Open], src.[Tuesday_Close], src.[Wednesday_Open], src.[Wednesday_Close], src.[Thursday_Open], src.[Thursday_Close], src.[Friday_Open], src.[Friday_Close], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Sites] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Site_ID] = src.[Site_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Sites] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Site_ID] = tgt.[Site_ID]
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