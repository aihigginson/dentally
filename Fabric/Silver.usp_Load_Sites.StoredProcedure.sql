--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Sites] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Sites
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
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
        ISNULL(CAST(staged.[Practice_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[address_line_1] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[address_line_2] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[town] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[postcode] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[phone_number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[website] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[logo_url] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[default_payment_plan_id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[monday_open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[monday_close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[tuesday_open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[tuesday_close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[wednesday_open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[wednesday_close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[thursday_open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[thursday_close] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[friday_open] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[friday_close] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(Site_ID,       50)  AS [Site_Id],
                LEFT(Practice_ID,   50)  AS [Practice_Id],
                Name  AS [Name],
                TRY_CAST(ROUND(CAST(Active AS float),0) AS int)  AS [active],
                Address_Line_1  AS [address_line_1],
                Address_Line_2  AS [address_line_2],
                Town  AS [town],
                Postcode  AS [postcode],
                Phone_Number  AS [phone_number],
                Website  AS [website],
                Logo_Url  AS [logo_url],
                -- Bronze Default_Payment_Plan_ID is decimal(18,4); Silver is VARCHAR(255)
        LEFT(CAST(TRY_CAST(ROUND(CAST(Default_Payment_Plan_ID AS float),0) AS bigint) AS VARCHAR(255)), 255)  AS [default_payment_plan_id],
                Monday_Open  AS [monday_open],
                Monday_Close  AS [monday_close],
                Tuesday_Open  AS [tuesday_open],
                Tuesday_Close  AS [tuesday_close],
                Wednesday_Open  AS [wednesday_open],
                Wednesday_Close  AS [wednesday_close],
                Thursday_Open  AS [thursday_open],
                Thursday_Close  AS [thursday_close],
                Friday_Open  AS [friday_open],
                Friday_Close  AS [friday_close]
            FROM Bronze.Sites
        ) AS staged;

        UPDATE tgt
        SET
            [Practice_Id] = src.[Practice_Id],
            [Name] = src.[Name],
            [active] = src.[active],
            [address_line_1] = src.[address_line_1],
            [address_line_2] = src.[address_line_2],
            [town] = src.[town],
            [postcode] = src.[postcode],
            [phone_number] = src.[phone_number],
            [website] = src.[website],
            [logo_url] = src.[logo_url],
            [default_payment_plan_id] = src.[default_payment_plan_id],
            [monday_open] = src.[monday_open],
            [monday_close] = src.[monday_close],
            [tuesday_open] = src.[tuesday_open],
            [tuesday_close] = src.[tuesday_close],
            [wednesday_open] = src.[wednesday_open],
            [wednesday_close] = src.[wednesday_close],
            [thursday_open] = src.[thursday_open],
            [thursday_close] = src.[thursday_close],
            [friday_open] = src.[friday_open],
            [friday_close] = src.[friday_close],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Sites] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Site_Id] = src.[Site_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Sites] ([Tenant_ID], [Site_Id], [Practice_Id], [Name], [active], [address_line_1], [address_line_2], [town], [postcode], [phone_number], [website], [logo_url], [default_payment_plan_id], [monday_open], [monday_close], [tuesday_open], [tuesday_close], [wednesday_open], [wednesday_close], [thursday_open], [thursday_close], [friday_open], [friday_close], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Site_Id], src.[Practice_Id], src.[Name], src.[active], src.[address_line_1], src.[address_line_2], src.[town], src.[postcode], src.[phone_number], src.[website], src.[logo_url], src.[default_payment_plan_id], src.[monday_open], src.[monday_close], src.[tuesday_open], src.[tuesday_close], src.[wednesday_open], src.[wednesday_close], src.[thursday_open], src.[thursday_close], src.[friday_open], src.[friday_close], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Sites] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Site_Id] = src.[Site_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Sites] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Site_Id] = tgt.[Site_Id]
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