--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Contracts] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Contracts
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     19/05/2026  AIH Read Name, Notes from Bronze (now available)
--    *03     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS, PDS, UDA, UOA)
--    *04     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
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
        ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Contract_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Location_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Notes] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[PDS_Plus] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Start_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[End_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Target] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[UDA_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[UOA_Target] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[UOA_Value] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [Id],
                LEFT(Site_ID, 50)  AS [Site_ID],
                CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Active],
                LEFT(Contract_Number, 50)  AS [Contract_Number],
                LEFT(Name, 255)  AS [Name],
                LEFT(NHS_Location_ID, 50)  AS [NHS_Location_ID],
                LEFT(NHS_Site_ID, 50)  AS [NHS_Site_ID],
                Notes  AS [Notes],
                CASE WHEN LOWER(TRIM(PDS_Plus)) IN ('true','1') THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [PDS_Plus],
                TRY_CAST(Start_Date AS date)  AS [Start_Date],
                TRY_CAST(End_Date   AS date)  AS [End_Date],
                TRY_CAST(Target     AS decimal(18,4))  AS [Target],
                TRY_CAST(UDA_Value  AS decimal(18,4))  AS [UDA_Value],
                TRY_CAST(UOA_Target AS decimal(18,4))  AS [UOA_Target],
                TRY_CAST(UOA_Value  AS decimal(18,4))  AS [UOA_Value]
            FROM Bronze.Contracts
        ) AS staged;

        UPDATE tgt
        SET
            [Site_ID] = src.[Site_ID],
            [Active] = src.[Active],
            [Contract_Number] = src.[Contract_Number],
            [Name] = src.[Name],
            [NHS_Location_ID] = src.[NHS_Location_ID],
            [NHS_Site_ID] = src.[NHS_Site_ID],
            [Notes] = src.[Notes],
            [PDS_Plus] = src.[PDS_Plus],
            [Start_Date] = src.[Start_Date],
            [End_Date] = src.[End_Date],
            [Target] = src.[Target],
            [UDA_Value] = src.[UDA_Value],
            [UOA_Target] = src.[UOA_Target],
            [UOA_Value] = src.[UOA_Value],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Contracts] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Contracts] ([Tenant_ID], [Id], [Site_ID], [Active], [Contract_Number], [Name], [NHS_Location_ID], [NHS_Site_ID], [Notes], [PDS_Plus], [Start_Date], [End_Date], [Target], [UDA_Value], [UOA_Target], [UOA_Value], [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Tenant_ID], src.[Id], src.[Site_ID], src.[Active], src.[Contract_Number], src.[Name], src.[NHS_Location_ID], src.[NHS_Site_ID], src.[Notes], src.[PDS_Plus], src.[Start_Date], src.[End_Date], src.[Target], src.[UDA_Value], src.[UOA_Target], src.[UOA_Value], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
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