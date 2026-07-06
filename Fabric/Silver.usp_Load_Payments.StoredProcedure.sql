--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Payments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Payments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *03     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Payments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Payments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Payments]
GO
CREATE PROCEDURE [Silver].[usp_Load_Payments]
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
        ISNULL(CAST(staged.[Account_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reference] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transaction_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Amount] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Amount_Unexplained] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Method] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Fully_Explained] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Deleted] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Dated_On] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                TRY_CAST(ROUND(TRY_CAST(Payment_ID AS float), 0) AS int)  AS [Payment_ID],
                TRY_CAST(ROUND(TRY_CAST(Account_ID AS float), 0) AS int)  AS [Account_ID],
                TRY_CAST(ROUND(TRY_CAST(Patient_ID AS float), 0) AS int)  AS [Patient_ID],
                Practitioner_ID  AS [Practitioner_ID],
                Payment_Plan_ID  AS [Payment_Plan_ID],
                LEFT(Site_ID, 50)  AS [Site_ID],
                User_ID  AS [User_ID],
                -- Reference/Transaction_Number: strip the trailing .0 when numeric (mock),
                -- else keep the raw string (real Dentally uses Stripe charge ids e.g. ch_...).
        LEFT(COALESCE(CAST(TRY_CAST(ROUND(TRY_CAST(Reference AS float),0) AS bigint) AS VARCHAR(50)), Reference), 50)  AS [Reference],
                LEFT(COALESCE(CAST(TRY_CAST(ROUND(TRY_CAST(Transaction_Number AS float),0) AS bigint) AS VARCHAR(50)), Transaction_Number), 50)  AS [Transaction_Number],
                Amount  AS [Amount],
                Amount_Unexplained  AS [Amount_Unexplained],
                LEFT(Method, 100)  AS [Method],
                CASE WHEN LOWER(TRIM(Fully_Explained)) IN ('true','1') THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Fully_Explained],
                CASE WHEN LOWER(TRIM(Deleted))         IN ('true','1') THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Deleted],
                LEFT(Status, 50)  AS [Status],
                TRY_CAST(Dated_On AS date)  AS [Dated_On]
            FROM Bronze.Payments
            WHERE TRY_CAST(ROUND(TRY_CAST(Payment_ID AS float), 0) AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Account_ID] = src.[Account_ID],
            [Patient_ID] = src.[Patient_ID],
            [Practitioner_ID] = src.[Practitioner_ID],
            [Payment_Plan_ID] = src.[Payment_Plan_ID],
            [Site_ID] = src.[Site_ID],
            [User_ID] = src.[User_ID],
            [Reference] = src.[Reference],
            [Transaction_Number] = src.[Transaction_Number],
            [Amount] = src.[Amount],
            [Amount_Unexplained] = src.[Amount_Unexplained],
            [Method] = src.[Method],
            [Fully_Explained] = src.[Fully_Explained],
            [Deleted] = src.[Deleted],
            [Status] = src.[Status],
            [Dated_On] = src.[Dated_On],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Payments] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Payment_ID] = src.[Payment_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Payments] ([Tenant_ID], [Payment_ID], [Account_ID], [Patient_ID], [Practitioner_ID], [Payment_Plan_ID], [Site_ID], [User_ID], [Reference], [Transaction_Number], [Amount], [Amount_Unexplained], [Method], [Fully_Explained], [Deleted], [Status], [Dated_On],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Payment_ID], src.[Account_ID], src.[Patient_ID], src.[Practitioner_ID], src.[Payment_Plan_ID], src.[Site_ID], src.[User_ID], src.[Reference], src.[Transaction_Number], src.[Amount], src.[Amount_Unexplained], src.[Method], src.[Fully_Explained], src.[Deleted], src.[Status], src.[Dated_On],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Payments] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Payment_ID] = src.[Payment_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Payments] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Payment_ID] = tgt.[Payment_ID]
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
