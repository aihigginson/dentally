--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Practice
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Practice @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Practice]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Practice]
GO
CREATE PROCEDURE [Silver].[usp_Load_Practice]
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
        ISNULL(CAST(staged.[Practice_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Email_Address] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Phone_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Address_Line_1] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Address_Line_2] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Town] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[County] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Postcode] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Country] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Time_Zone] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Website] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(Practice_ID, 50)  AS [Practice_Id],
                Practice_Name  AS [Practice_Name],
                Email_Address  AS [Email_Address],
                LEFT(CAST(TRY_CAST(ROUND(CAST(Phone_Number AS float),0) AS bigint) AS VARCHAR(50)), 50)  AS [Phone_Number],
                Address_Line_1  AS [Address_Line_1],
                Address_Line_2  AS [Address_Line_2],
                NULL  AS [Town],
                -- Town not present in Bronze.Practice
        NULL  AS [County],
                -- County not present in Bronze.Practice
        LEFT(Postcode, 20)  AS [Postcode],
                NULL  AS [Country],
                TRY_CAST(ROUND(CAST(NHS AS float),0) AS int)  AS [NHS],
                LEFT(Time_Zone, 50)  AS [Time_Zone],
                LEFT(Website, 200)  AS [Website]
            FROM Bronze.Practice
        ) AS staged;

        UPDATE tgt
        SET
            [Practice_Name] = src.[Practice_Name],
            [Email_Address] = src.[Email_Address],
            [Phone_Number] = src.[Phone_Number],
            [Address_Line_1] = src.[Address_Line_1],
            [Address_Line_2] = src.[Address_Line_2],
            [Town] = src.[Town],
            [County] = src.[County],
            [Postcode] = src.[Postcode],
            [Country] = src.[Country],
            [NHS] = src.[NHS],
            [Time_Zone] = src.[Time_Zone],
            [Website] = src.[Website],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Practice] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Practice_Id] = src.[Practice_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Practice] ([Tenant_ID], [Practice_Id], [Practice_Name], [Email_Address], [Phone_Number], [Address_Line_1], [Address_Line_2], [Town], [County], [Postcode], [Country], [NHS], [Time_Zone], [Website],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Tenant_ID], src.[Practice_Id], src.[Practice_Name], src.[Email_Address], src.[Phone_Number], src.[Address_Line_1], src.[Address_Line_2], src.[Town], src.[County], src.[Postcode], src.[Country], src.[NHS], src.[Time_Zone], src.[Website],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Practice] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Practice_Id] = src.[Practice_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Practice] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Practice_Id] = tgt.[Practice_Id]
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