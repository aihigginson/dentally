/****** Object:  StoredProcedure [Silver].[usp_Load_Invoices]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Invoices]
GO
CREATE PROCEDURE [Silver].[usp_Load_Invoices]
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
        ISNULL(CAST(staged.[Account_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reference] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Amount] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Amount_Outstanding] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nhs_Amount] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Paid] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Dated_On] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Due_On] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Paid_On] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Terms] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Footnote] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Sent_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                ID  AS [Id],
                Account_ID  AS [Account_Id],
                Patient_ID  AS [Patient_Id],
                LEFT(Site_ID, 50)  AS [Site_Id],
                -- Bronze User_ID is int; Silver is VARCHAR(50)
        CASE WHEN User_ID IS NULL THEN NULL
             ELSE LEFT(CAST(User_ID AS VARCHAR(50)), 50)
        END  AS [User_Id],
                LEFT(Reference, 50)  AS [Reference],
                Amount  AS [Amount],
                Amount_Outstanding  AS [Amount_Outstanding],
                TRY_CAST(NHS_Amount AS decimal(18,4))  AS [Nhs_Amount],
                -- Derive paid flag: paid if outstanding balance = 0 and amount > 0
        CASE WHEN Amount_Outstanding = 0 AND Amount > 0
             THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Paid],
                TRY_CAST(Dated_On AS date)  AS [Dated_On],
                TRY_CAST(Due_On   AS date)  AS [Due_On],
                TRY_CAST(Paid_On  AS date)  AS [Paid_On],
                Payment_Terms  AS [Payment_Terms],
                Footnote  AS [Footnote],
                CAST(NULL AS datetime2(3))  AS [Sent_At],
                -- Bronze has no Sent_At
        NULL  AS [Status]
                -- Bronze has no Status
            FROM Bronze.Invoices
        ) AS staged;

        UPDATE tgt
        SET
            [Account_Id] = src.[Account_Id],
            [Patient_Id] = src.[Patient_Id],
            [Site_Id] = src.[Site_Id],
            [User_Id] = src.[User_Id],
            [Reference] = src.[Reference],
            [Amount] = src.[Amount],
            [Amount_Outstanding] = src.[Amount_Outstanding],
            [Nhs_Amount] = src.[Nhs_Amount],
            [Paid] = src.[Paid],
            [Dated_On] = src.[Dated_On],
            [Due_On] = src.[Due_On],
            [Paid_On] = src.[Paid_On],
            [Payment_Terms] = src.[Payment_Terms],
            [Footnote] = src.[Footnote],
            [Sent_At] = src.[Sent_At],
            [Status] = src.[Status],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Invoices] AS tgt
        INNER JOIN #src AS src ON tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Invoices] ([Id], [Account_Id], [Patient_Id], [Site_Id], [User_Id], [Reference], [Amount], [Amount_Outstanding], [Nhs_Amount], [Paid], [Dated_On], [Due_On], [Paid_On], [Payment_Terms], [Footnote], [Sent_At], [Status], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Id], src.[Account_Id], src.[Patient_Id], src.[Site_Id], src.[User_Id], src.[Reference], src.[Amount], src.[Amount_Outstanding], src.[Nhs_Amount], src.[Paid], src.[Dated_On], src.[Due_On], src.[Paid_On], src.[Payment_Terms], src.[Footnote], src.[Sent_At], src.[Status], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Invoices] AS tgt WHERE tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Invoices] AS tgt
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