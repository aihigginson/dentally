/****** Object:  StoredProcedure [Silver].[usp_Load_Treatment_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Treatment_Appointments]
GO
CREATE PROCEDURE [Silver].[usp_Load_Treatment_Appointments]
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
        ISNULL(CAST(staged.[Appointment_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Plan_Item_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Plan_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Position] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Bookable] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Notes] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                LEFT(ID, 50)  AS [Id],
                Appointment_ID  AS [Appointment_Id],
                NULL  AS [Treatment_Plan_Item_Id],
                -- Treatment_Plan_Item_Id not in Bronze
        Treatment_Plan_ID  AS [Treatment_Plan_Id],
                Patient_ID  AS [Patient_Id],
                NULL  AS [Practitioner_Id],
                -- Practitioner_Id not in Bronze
        NULL  AS [Site_Id],
                -- Site_Id not in Bronze
        NULL  AS [Status],
                -- Status not in Bronze
        Position  AS [Position],
                Bookable  AS [Bookable],
                Notes  AS [Notes]
            FROM Bronze.Treatment_Appointments
        ) AS staged;

        UPDATE tgt
        SET
            [Appointment_Id] = src.[Appointment_Id],
            [Treatment_Plan_Item_Id] = src.[Treatment_Plan_Item_Id],
            [Treatment_Plan_Id] = src.[Treatment_Plan_Id],
            [Patient_Id] = src.[Patient_Id],
            [Practitioner_Id] = src.[Practitioner_Id],
            [Site_Id] = src.[Site_Id],
            [Status] = src.[Status],
            [Position] = src.[Position],
            [Bookable] = src.[Bookable],
            [Notes] = src.[Notes],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Treatment_Appointments] AS tgt
        INNER JOIN #src AS src ON tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Treatment_Appointments] ([Id], [Appointment_Id], [Treatment_Plan_Item_Id], [Treatment_Plan_Id], [Patient_Id], [Practitioner_Id], [Site_Id], [Status], [Position], [Bookable], [Notes], [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Id], src.[Appointment_Id], src.[Treatment_Plan_Item_Id], src.[Treatment_Plan_Id], src.[Patient_Id], src.[Practitioner_Id], src.[Site_Id], src.[Status], src.[Position], src.[Bookable], src.[Notes], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Treatment_Appointments] AS tgt WHERE tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Treatment_Appointments] AS tgt
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