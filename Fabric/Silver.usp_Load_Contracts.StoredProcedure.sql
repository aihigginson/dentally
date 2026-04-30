--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Contracts
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Contracts @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Contracts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Contracts]
GO
CREATE PROCEDURE [Silver].[usp_Load_Contracts]
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
        ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Contract_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nhs_Location_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nhs_Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Notes] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Pds_Plus] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Start_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[End_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Target] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Uda_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Uoa_Target] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Uoa_Value] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [Id],
                LEFT(Site_ID, 50)  AS [Site_Id],
                CASE WHEN Active = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Active],
                LEFT(Contract_Number, 50)  AS [Contract_Number],
                NULL  AS [Name],
                -- Bronze has no Name column
        LEFT(NHS_Location_ID, 50)  AS [Nhs_Location_Id],
                LEFT(NHS_Site_ID, 50)  AS [Nhs_Site_Id],
                NULL  AS [Notes],
                -- Bronze has no Notes column
        CASE WHEN Pds_Plus = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Pds_Plus],
                TRY_CAST(Start_Date AS date)  AS [Start_Date],
                TRY_CAST(End_Date   AS date)  AS [End_Date],
                TRY_CAST(Target     AS decimal(18,4))  AS [Target],
                TRY_CAST(UDA_Value  AS decimal(18,4))  AS [Uda_Value],
                TRY_CAST(UOA_Target AS decimal(18,4))  AS [Uoa_Target],
                TRY_CAST(UOA_Value  AS decimal(18,4))  AS [Uoa_Value]
            FROM Bronze.Contracts
        ) AS staged;

        UPDATE tgt
        SET
            [Site_Id] = src.[Site_Id],
            [Active] = src.[Active],
            [Contract_Number] = src.[Contract_Number],
            [Name] = src.[Name],
            [Nhs_Location_Id] = src.[Nhs_Location_Id],
            [Nhs_Site_Id] = src.[Nhs_Site_Id],
            [Notes] = src.[Notes],
            [Pds_Plus] = src.[Pds_Plus],
            [Start_Date] = src.[Start_Date],
            [End_Date] = src.[End_Date],
            [Target] = src.[Target],
            [Uda_Value] = src.[Uda_Value],
            [Uoa_Target] = src.[Uoa_Target],
            [Uoa_Value] = src.[Uoa_Value],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Contracts] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Contracts] ([Tenant_ID], [Id], [Site_Id], [Active], [Contract_Number], [Name], [Nhs_Location_Id], [Nhs_Site_Id], [Notes], [Pds_Plus], [Start_Date], [End_Date], [Target], [Uda_Value], [Uoa_Target], [Uoa_Value], [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Tenant_ID], src.[Id], src.[Site_Id], src.[Active], src.[Contract_Number], src.[Name], src.[Nhs_Location_Id], src.[Nhs_Site_Id], src.[Notes], src.[Pds_Plus], src.[Start_Date], src.[End_Date], src.[Target], src.[Uda_Value], src.[Uoa_Target], src.[Uoa_Value], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Contracts] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Contracts] AS tgt
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