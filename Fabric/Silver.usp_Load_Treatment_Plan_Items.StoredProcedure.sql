--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Treatment_Plan_Items] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Treatment_Plan_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     18/05/2026  AIH Fix Id conversion: Bronze ID is now VARCHAR(50) not DECIMAL
--    *03     19/05/2026  AIH Read Surfaces→Surface and Teeth→Tooth from Bronze (now populated)
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS)
--    *05     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Treatment_Plan_Items @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Treatment_Plan_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Treatment_Plan_Items]
GO
CREATE PROCEDURE [Silver].[usp_Load_Treatment_Plan_Items]
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
        ISNULL(CAST(staged.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Fee_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Quantity] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Price] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Total_Price] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Tooth] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Surface] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Region] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Invoice_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Appointment_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Referrer_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nomenclature] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[UDA_Band] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Position] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Base_Chart] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Completed] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Charged] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Appear_On_Invoice] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Completed_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
        LEFT(ID, 50)  AS [Id],
                -- Bronze Treatment_Plan_ID is VARCHAR(255); Silver is int
        TRY_CAST(Treatment_Plan_ID AS int)  AS [Treatment_Plan_ID],
                Payment_Plan_ID  AS [Payment_Plan_ID],
                -- Bronze Treatment_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(TRY_CAST(Treatment_ID AS float),0) AS int)  AS [Treatment_ID],
                -- Bronze Patient_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(TRY_CAST(Patient_ID AS float),0) AS int)  AS [Patient_ID],
                Practitioner_ID  AS [Practitioner_ID],
                CAST(NULL AS uniqueidentifier)  AS [Fee_ID],
                -- Fee_ID not in Bronze
        NULL  AS [Name],
                -- Name not in Bronze (Nomenclature used instead)
        NULL  AS [Quantity],
                -- Quantity not in Bronze
        Price  AS [Price],
                NULL  AS [Total_Price],
                -- Total_Price not in Bronze
        NULL  AS [NHS_Charge],
                -- NHS_Charge not in Bronze
        NULL  AS [Status],
                -- Status not in Bronze
        LEFT(Teeth,    50)  AS [Tooth],
                LEFT(Surfaces, 50)  AS [Surface],
                LEFT(Region,   50)  AS [Region],
                LEFT(Invoice_ID, 255)  AS [Invoice_ID],
                LEFT(Treatment_Appointment_ID, 255)  AS [Treatment_Appointment_ID],
                -- Bronze Referrer_ID is decimal(18,4); Silver is VARCHAR(255)
        LEFT(CAST(TRY_CAST(ROUND(TRY_CAST(Referrer_ID AS float),0) AS bigint) AS VARCHAR(255)), 255)  AS [Referrer_ID],
                LEFT(Nomenclature,         255)  AS [Nomenclature],
                LEFT(NHS_Treatment_Cat,    255)  AS [NHS_Treatment_Cat],
                LEFT(UDA_Band,             255)  AS [UDA_Band],
                TRY_CAST(ROUND(TRY_CAST(Position AS float),0) AS int)  AS [Position],
                TRY_CAST(ROUND(TRY_CAST(Base_Chart AS float),0) AS int)  AS [Base_Chart],
                CASE WHEN LOWER(TRIM(Completed))       IN ('true','1') THEN 1 ELSE 0 END  AS [Completed],
                CASE WHEN LOWER(TRIM(Charged))         IN ('true','1') THEN 1 ELSE 0 END  AS [Charged],
                CASE WHEN LOWER(TRIM(Appear_On_Invoice)) IN ('true','1') THEN 1 ELSE 0 END  AS [Appear_On_Invoice],
                TRY_CAST(ROUND(TRY_CAST(Duration AS float),0) AS int)  AS [Duration],
                LEFT(Completed_At, 50)  AS [Completed_At],
                LEFT(Created_At,   50)  AS [Created_At],
                LEFT(Updated_At,   50)  AS [Updated_At]
            FROM Bronze.Treatment_Plan_Items
            WHERE ID IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Treatment_Plan_ID] = src.[Treatment_Plan_ID],
            [Payment_Plan_ID] = src.[Payment_Plan_ID],
            [Treatment_ID] = src.[Treatment_ID],
            [Patient_ID] = src.[Patient_ID],
            [Practitioner_ID] = src.[Practitioner_ID],
            [Fee_ID] = src.[Fee_ID],
            [Name] = src.[Name],
            [Quantity] = src.[Quantity],
            [Price] = src.[Price],
            [Total_Price] = src.[Total_Price],
            [NHS_Charge] = src.[NHS_Charge],
            [Status] = src.[Status],
            [Tooth] = src.[Tooth],
            [Surface] = src.[Surface],
            [Region] = src.[Region],
            [Invoice_ID] = src.[Invoice_ID],
            [Treatment_Appointment_ID] = src.[Treatment_Appointment_ID],
            [Referrer_ID] = src.[Referrer_ID],
            [Nomenclature] = src.[Nomenclature],
            [NHS_Treatment_Cat] = src.[NHS_Treatment_Cat],
            [UDA_Band] = src.[UDA_Band],
            [Position] = src.[Position],
            [Base_Chart] = src.[Base_Chart],
            [Completed] = src.[Completed],
            [Charged] = src.[Charged],
            [Appear_On_Invoice] = src.[Appear_On_Invoice],
            [Duration] = src.[Duration],
            [Completed_At] = src.[Completed_At],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Treatment_Plan_Items] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Treatment_Plan_Items] ([Tenant_ID], [Id], [Treatment_Plan_ID], [Payment_Plan_ID], [Treatment_ID], [Patient_ID], [Practitioner_ID], [Fee_ID], [Name], [Quantity], [Price], [Total_Price], [NHS_Charge], [Status], [Tooth], [Surface], [Region], [Invoice_ID], [Treatment_Appointment_ID], [Referrer_ID], [Nomenclature], [NHS_Treatment_Cat], [UDA_Band], [Position], [Base_Chart], [Completed], [Charged], [Appear_On_Invoice], [Duration], [Completed_At], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Id], src.[Treatment_Plan_ID], src.[Payment_Plan_ID], src.[Treatment_ID], src.[Patient_ID], src.[Practitioner_ID], src.[Fee_ID], src.[Name], src.[Quantity], src.[Price], src.[Total_Price], src.[NHS_Charge], src.[Status], src.[Tooth], src.[Surface], src.[Region], src.[Invoice_ID], src.[Treatment_Appointment_ID], src.[Referrer_ID], src.[Nomenclature], src.[NHS_Treatment_Cat], src.[UDA_Band], src.[Position], src.[Base_Chart], src.[Completed], src.[Charged], src.[Appear_On_Invoice], src.[Duration], src.[Completed_At], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Treatment_Plan_Items] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Treatment_Plan_Items] AS tgt
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
