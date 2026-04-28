/****** Object:  StoredProcedure [Silver].[usp_Load_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Appointments]
GO
CREATE PROCEDURE [Silver].[usp_Load_Appointments]
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
        ISNULL(CAST(staged.[Appointment_Uuid] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Appointment_Cancellation_Reason_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Image_Url] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Room_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Start_Time] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Finish_Time] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reason] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[State] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Notes] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Description] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Booked_Via_Api] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Pending_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Confirmed_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Arrived_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[In_Surgery_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Completed_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Cancelled_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Did_Not_Attend_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Metadata_1_Key] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Metadata_1_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Metadata_2_Key] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Metadata_2_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Metadata_3_Key] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Metadata_3_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                ID  AS [Appointment_Id],
                LEFT(UUID, 50)  AS [Appointment_Uuid],
                -- Bronze stores cancellation reason as int; Silver is VARCHAR(50)
        CASE WHEN Appointment_Cancellation_Reason_ID IS NULL
             THEN NULL
             ELSE LEFT(CAST(Appointment_Cancellation_Reason_ID AS VARCHAR(50)), 50)
        END  AS [Appointment_Cancellation_Reason_Id],
                Patient_ID  AS [Patient_Id],
                Patient_Name  AS [Patient_Name],
                LEFT(Patient_Image_Url, 500)  AS [Patient_Image_Url],
                Practitioner_ID  AS [Practitioner_Id],
                User_ID  AS [User_Id],
                Payment_Plan_ID  AS [Payment_Plan_Id],
                LEFT(Room_ID, 50)  AS [Room_Id],
                LEFT(Start_Time,  50)  AS [Start_Time],
                LEFT(Finish_Time, 50)  AS [Finish_Time],
                Duration  AS [Duration],
                LEFT(Reason, 100)  AS [Reason],
                LEFT(State,  50)  AS [State],
                Notes  AS [Notes],
                -- VARCHAR(max) → VARCHAR(max)  OK
        Treatment_Description  AS [Treatment_Description],
                -- Bronze Booked_Via_API is int; Silver is bit
        CASE WHEN Booked_Via_API = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Booked_Via_Api],
                LEFT(Pending_At,        50)  AS [Pending_At],
                LEFT(Confirmed_At,      50)  AS [Confirmed_At],
                LEFT(Arrived_At,        50)  AS [Arrived_At],
                LEFT(In_Surgery_At,     50)  AS [In_Surgery_At],
                LEFT(Completed_At,      50)  AS [Completed_At],
                LEFT(Cancelled_At,      50)  AS [Cancelled_At],
                LEFT(Did_Not_Attend_At, 50)  AS [Did_Not_Attend_At],
                -- Metadata columns have no Bronze source; leave NULL
        NULL  AS [Metadata_1_Key],
                NULL  AS [Metadata_1_Value],
                NULL  AS [Metadata_2_Key],
                NULL  AS [Metadata_2_Value],
                NULL  AS [Metadata_3_Key],
                NULL  AS [Metadata_3_Value],
                LEFT(Created_At, 50)  AS [Created_At],
                LEFT(Updated_At, 50)  AS [Updated_At]
            FROM Bronze.Appointments
        ) AS staged;

        UPDATE tgt
        SET
            [Appointment_Uuid] = src.[Appointment_Uuid],
            [Appointment_Cancellation_Reason_Id] = src.[Appointment_Cancellation_Reason_Id],
            [Patient_Id] = src.[Patient_Id],
            [Patient_Name] = src.[Patient_Name],
            [Patient_Image_Url] = src.[Patient_Image_Url],
            [Practitioner_Id] = src.[Practitioner_Id],
            [User_Id] = src.[User_Id],
            [Payment_Plan_Id] = src.[Payment_Plan_Id],
            [Room_Id] = src.[Room_Id],
            [Start_Time] = src.[Start_Time],
            [Finish_Time] = src.[Finish_Time],
            [Duration] = src.[Duration],
            [Reason] = src.[Reason],
            [State] = src.[State],
            [Notes] = src.[Notes],
            [Treatment_Description] = src.[Treatment_Description],
            [Booked_Via_Api] = src.[Booked_Via_Api],
            [Pending_At] = src.[Pending_At],
            [Confirmed_At] = src.[Confirmed_At],
            [Arrived_At] = src.[Arrived_At],
            [In_Surgery_At] = src.[In_Surgery_At],
            [Completed_At] = src.[Completed_At],
            [Cancelled_At] = src.[Cancelled_At],
            [Did_Not_Attend_At] = src.[Did_Not_Attend_At],
            [Metadata_1_Key] = src.[Metadata_1_Key],
            [Metadata_1_Value] = src.[Metadata_1_Value],
            [Metadata_2_Key] = src.[Metadata_2_Key],
            [Metadata_2_Value] = src.[Metadata_2_Value],
            [Metadata_3_Key] = src.[Metadata_3_Key],
            [Metadata_3_Value] = src.[Metadata_3_Value],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Appointments] AS tgt
        INNER JOIN #src AS src ON tgt.[Appointment_Id] = src.[Appointment_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Appointments] ([Appointment_Id], [Appointment_Uuid], [Appointment_Cancellation_Reason_Id], [Patient_Id], [Patient_Name], [Patient_Image_Url], [Practitioner_Id], [User_Id], [Payment_Plan_Id], [Room_Id], [Start_Time], [Finish_Time], [Duration], [Reason], [State], [Notes], [Treatment_Description], [Booked_Via_Api], [Pending_At], [Confirmed_At], [Arrived_At], [In_Surgery_At], [Completed_At], [Cancelled_At], [Did_Not_Attend_At], [Metadata_1_Key], [Metadata_1_Value], [Metadata_2_Key], [Metadata_2_Value], [Metadata_3_Key], [Metadata_3_Value], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Appointment_Id], src.[Appointment_Uuid], src.[Appointment_Cancellation_Reason_Id], src.[Patient_Id], src.[Patient_Name], src.[Patient_Image_Url], src.[Practitioner_Id], src.[User_Id], src.[Payment_Plan_Id], src.[Room_Id], src.[Start_Time], src.[Finish_Time], src.[Duration], src.[Reason], src.[State], src.[Notes], src.[Treatment_Description], src.[Booked_Via_Api], src.[Pending_At], src.[Confirmed_At], src.[Arrived_At], src.[In_Surgery_At], src.[Completed_At], src.[Cancelled_At], src.[Did_Not_Attend_At], src.[Metadata_1_Key], src.[Metadata_1_Value], src.[Metadata_2_Key], src.[Metadata_2_Value], src.[Metadata_3_Key], src.[Metadata_3_Value], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Appointments] AS tgt WHERE tgt.[Appointment_Id] = src.[Appointment_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Appointments] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Appointment_Id] = tgt.[Appointment_Id]
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
