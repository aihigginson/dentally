--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Appointments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Appointments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     14/05/2026  AIH Add Site_Id from Bronze
--    *03     19/05/2026  AIH Set Site_Id, Created_At, Updated_At to NULL (removed from Bronze -- not in Dentally API)
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID, UUID, API)
--    *05     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--    *06     02/06/2026  AIH Derive Site_ID via LEFT JOIN Silver.Rooms on Room_ID (not in Dentally API direct)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Appointments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
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
        ISNULL(CAST(staged.[Appointment_UUID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Appointment_Cancellation_Reason_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Image_Url] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Room_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Start_Time] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Finish_Time] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reason] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[State] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Notes] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Description] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Booked_Via_API] AS VARCHAR(500)), ''),
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
                a.Tenant_ID  AS [Tenant_ID],
                ID  AS [Appointment_ID],
                LEFT(UUID, 50)  AS [Appointment_UUID],
                -- Bronze stores cancellation reason as int; Silver is VARCHAR(50)
        CASE WHEN Appointment_Cancellation_Reason_ID IS NULL
             THEN NULL
             ELSE LEFT(CAST(Appointment_Cancellation_Reason_ID AS VARCHAR(50)), 50)
        END  AS [Appointment_Cancellation_Reason_ID],
                Patient_ID  AS [Patient_ID],
                Patient_Name  AS [Patient_Name],
                LEFT(Patient_Image_Url, 500)  AS [Patient_Image_Url],
                Practitioner_ID  AS [Practitioner_ID],
                User_ID  AS [User_ID],
                Payment_Plan_ID  AS [Payment_Plan_ID],
                LEFT(a.Room_ID, 50)  AS [Room_ID],
                r.Site_ID            AS [Site_ID],
                LEFT(Start_Time,  50)  AS [Start_Time],
                LEFT(Finish_Time, 50)  AS [Finish_Time],
                Duration  AS [Duration],
                LEFT(Reason, 100)  AS [Reason],
                LEFT(State,  50)  AS [State],
                Notes  AS [Notes],
                -- VARCHAR(max) → VARCHAR(max)  OK
        Treatment_Description  AS [Treatment_Description],
                -- Bronze Booked_Via_API is VARCHAR; Silver is bit
        CASE WHEN LOWER(TRIM(Booked_Via_API)) IN ('true','1') THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Booked_Via_API],
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
                NULL  AS [Created_At],
                NULL  AS [Updated_At]
            FROM Bronze.Appointments a
            LEFT JOIN Silver.Rooms r ON r.Room_ID = LEFT(a.Room_ID, 50) AND r.Tenant_ID = a.Tenant_ID
        ) AS staged;

        UPDATE tgt
        SET
            [Appointment_UUID] = src.[Appointment_UUID],
            [Appointment_Cancellation_Reason_ID] = src.[Appointment_Cancellation_Reason_ID],
            [Patient_ID] = src.[Patient_ID],
            [Patient_Name] = src.[Patient_Name],
            [Patient_Image_Url] = src.[Patient_Image_Url],
            [Practitioner_ID] = src.[Practitioner_ID],
            [User_ID] = src.[User_ID],
            [Payment_Plan_ID] = src.[Payment_Plan_ID],
            [Room_ID] = src.[Room_ID],
            [Site_ID] = src.[Site_ID],
            [Start_Time] = src.[Start_Time],
            [Finish_Time] = src.[Finish_Time],
            [Duration] = src.[Duration],
            [Reason] = src.[Reason],
            [State] = src.[State],
            [Notes] = src.[Notes],
            [Treatment_Description] = src.[Treatment_Description],
            [Booked_Via_API] = src.[Booked_Via_API],
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
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Appointment_ID] = src.[Appointment_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Appointments] ([Tenant_ID], [Appointment_ID], [Appointment_UUID], [Appointment_Cancellation_Reason_ID], [Patient_ID], [Patient_Name], [Patient_Image_Url], [Practitioner_ID], [User_ID], [Payment_Plan_ID], [Room_ID], [Site_ID], [Start_Time], [Finish_Time], [Duration], [Reason], [State], [Notes], [Treatment_Description], [Booked_Via_API], [Pending_At], [Confirmed_At], [Arrived_At], [In_Surgery_At], [Completed_At], [Cancelled_At], [Did_Not_Attend_At], [Metadata_1_Key], [Metadata_1_Value], [Metadata_2_Key], [Metadata_2_Value], [Metadata_3_Key], [Metadata_3_Value], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Appointment_ID], src.[Appointment_UUID], src.[Appointment_Cancellation_Reason_ID], src.[Patient_ID], src.[Patient_Name], src.[Patient_Image_Url], src.[Practitioner_ID], src.[User_ID], src.[Payment_Plan_ID], src.[Room_ID], src.[Site_ID], src.[Start_Time], src.[Finish_Time], src.[Duration], src.[Reason], src.[State], src.[Notes], src.[Treatment_Description], src.[Booked_Via_API], src.[Pending_At], src.[Confirmed_At], src.[Arrived_At], src.[In_Surgery_At], src.[Completed_At], src.[Cancelled_At], src.[Did_Not_Attend_At], src.[Metadata_1_Key], src.[Metadata_1_Value], src.[Metadata_2_Key], src.[Metadata_2_Value], src.[Metadata_3_Key], src.[Metadata_3_Value], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Appointments] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Appointment_ID] = src.[Appointment_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Appointments] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Appointment_ID] = tgt.[Appointment_ID]
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
