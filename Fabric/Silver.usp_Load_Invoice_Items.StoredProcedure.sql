/****** Object:  StoredProcedure [Silver].[usp_Load_Invoice_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Invoice_Items]
GO
CREATE PROCEDURE [Silver].[usp_Load_Invoice_Items]
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
        ISNULL(CAST(staged.[Invoice_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Plan_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Plan_Item_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Sundry_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Quantity] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Item_Price] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Total_Price] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nhs_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                LEFT(ID, 50)  AS [Id],
                Invoice_ID  AS [Invoice_Id],
                Practitioner_ID  AS [Practitioner_Id],
                Treatment_Plan_ID  AS [Treatment_Plan_Id],
                -- Bronze Treatment_Plan_Item_ID is int; Silver is VARCHAR(50)
        CASE WHEN Treatment_Plan_Item_ID IS NULL THEN NULL
             ELSE LEFT(CAST(Treatment_Plan_Item_ID AS VARCHAR(50)), 50)
        END  AS [Treatment_Plan_Item_Id],
                LEFT(Sundry_ID, 255)  AS [Sundry_Id],
                -- Bronze User_ID is int; Silver is VARCHAR(255)
        CASE WHEN User_ID IS NULL THEN NULL
             ELSE LEFT(CAST(User_ID AS VARCHAR(255)), 255)
        END  AS [User_Id],
                Name  AS [Name],
                Quantity  AS [Quantity],
                -- Bronze Item_Price is int; Silver is decimal(18,4)
        CAST(Item_Price AS decimal(18,4))  AS [Item_Price],
                Total_Price  AS [Total_Price],
                -- Bronze NHS_Charge is int; Silver is bit
        CASE WHEN NHS_Charge = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Nhs_Charge],
                LEFT(Created_At, 255)  AS [Created_At],
                LEFT(Updated_At, 255)  AS [Updated_At]
            FROM Bronze.Invoice_Items
        ) AS staged;

        UPDATE tgt
        SET
            [Invoice_Id] = src.[Invoice_Id],
            [Practitioner_Id] = src.[Practitioner_Id],
            [Treatment_Plan_Id] = src.[Treatment_Plan_Id],
            [Treatment_Plan_Item_Id] = src.[Treatment_Plan_Item_Id],
            [Sundry_Id] = src.[Sundry_Id],
            [User_Id] = src.[User_Id],
            [Name] = src.[Name],
            [Quantity] = src.[Quantity],
            [Item_Price] = src.[Item_Price],
            [Total_Price] = src.[Total_Price],
            [Nhs_Charge] = src.[Nhs_Charge],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Invoice_Items] AS tgt
        INNER JOIN #src AS src ON tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Invoice_Items] ([Id], [Invoice_Id], [Practitioner_Id], [Treatment_Plan_Id], [Treatment_Plan_Item_Id], [Sundry_Id], [User_Id], [Name], [Quantity], [Item_Price], [Total_Price], [Nhs_Charge], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Id], src.[Invoice_Id], src.[Practitioner_Id], src.[Treatment_Plan_Id], src.[Treatment_Plan_Item_Id], src.[Sundry_Id], src.[User_Id], src.[Name], src.[Quantity], src.[Item_Price], src.[Total_Price], src.[Nhs_Charge], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Invoice_Items] AS tgt WHERE tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Invoice_Items] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Id] = tgt.[Id]
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
