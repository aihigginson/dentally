/****** Object:  StoredProcedure [Silver].[usp_Load_Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Recalls]
GO
CREATE PROCEDURE [Silver].[usp_Load_Recalls]
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
        ISNULL(CAST(staged.[Patient_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Appointment_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Recall_Method] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Workflow_Status] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Workflow_Stage_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[First_Reminder_Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Second_Reminder_Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[First_Reminder_Sent_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Second_Reminder_Sent_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Latest_Reminder_Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Reminded_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Times_Contacted] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Run_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Recall_Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Due_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Interval_Months] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Sent_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Booked_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                LEFT(ID, 50)  AS [Id],
                TRY_CAST(ROUND(CAST(Patient_ID AS float), 0) AS int)  AS [Patient_Id],
                NULL  AS [Practitioner_Id],
                -- Practitioner_Id not in Bronze.Recalls
        LEFT(Appointment_ID,          50)  AS [Appointment_ID],
                LEFT(Recall_Method,           50)  AS [Recall_Method],
                LEFT(Workflow_Status,         50)  AS [Workflow_Status],
                LEFT(Workflow_Stage_ID,       50)  AS [Workflow_Stage_ID],
                LEFT(First_Reminder_Type,     50)  AS [First_Reminder_Type],
                LEFT(Second_Reminder_Type,    50)  AS [Second_Reminder_Type],
                LEFT(First_Reminder_Sent_At,  50)  AS [First_Reminder_Sent_At],
                LEFT(Second_Reminder_Sent_At, 50)  AS [Second_Reminder_Sent_At],
                LEFT(Latest_Reminder_Type,    50)  AS [Latest_Reminder_Type],
                LEFT(Last_Reminded_At,        50)  AS [Last_Reminded_At],
                LEFT(CAST(TRY_CAST(ROUND(CAST(Times_Contacted AS float),0) AS bigint) AS VARCHAR(50)), 50)  AS [Times_Contacted],
                LEFT(Run_Date, 50)  AS [Run_Date],
                NULL  AS [Site_Id],
                -- Site_Id not in Bronze.Recalls
        LEFT(Recall_Type, 50)  AS [Recall_Type],
                TRY_CAST(Due_Date AS date)  AS [Due_Date],
                NULL  AS [Interval_Months],
                -- Interval_Months not in Bronze
        LEFT(Status, 50)  AS [Status],
                CAST(NULL AS datetime2(3))  AS [Sent_At],
                -- Sent_At not in Bronze
        CAST(NULL AS datetime2(3))  AS [Booked_At]
                -- Booked_At not in Bronze
            FROM Bronze.Recalls
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_Id] = src.[Patient_Id],
            [Practitioner_Id] = src.[Practitioner_Id],
            [Appointment_ID] = src.[Appointment_ID],
            [Recall_Method] = src.[Recall_Method],
            [Workflow_Status] = src.[Workflow_Status],
            [Workflow_Stage_ID] = src.[Workflow_Stage_ID],
            [First_Reminder_Type] = src.[First_Reminder_Type],
            [Second_Reminder_Type] = src.[Second_Reminder_Type],
            [First_Reminder_Sent_At] = src.[First_Reminder_Sent_At],
            [Second_Reminder_Sent_At] = src.[Second_Reminder_Sent_At],
            [Latest_Reminder_Type] = src.[Latest_Reminder_Type],
            [Last_Reminded_At] = src.[Last_Reminded_At],
            [Times_Contacted] = src.[Times_Contacted],
            [Run_Date] = src.[Run_Date],
            [Site_Id] = src.[Site_Id],
            [Recall_Type] = src.[Recall_Type],
            [Due_Date] = src.[Due_Date],
            [Interval_Months] = src.[Interval_Months],
            [Status] = src.[Status],
            [Sent_At] = src.[Sent_At],
            [Booked_At] = src.[Booked_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Recalls] AS tgt
        INNER JOIN #src AS src ON tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Recalls] ([Id], [Patient_Id], [Practitioner_Id], [Appointment_ID], [Recall_Method], [Workflow_Status], [Workflow_Stage_ID], [First_Reminder_Type], [Second_Reminder_Type], [First_Reminder_Sent_At], [Second_Reminder_Sent_At], [Latest_Reminder_Type], [Last_Reminded_At], [Times_Contacted], [Run_Date], [Site_Id], [Recall_Type], [Due_Date], [Interval_Months], [Status], [Sent_At], [Booked_At], [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Id], src.[Patient_Id], src.[Practitioner_Id], src.[Appointment_ID], src.[Recall_Method], src.[Workflow_Status], src.[Workflow_Stage_ID], src.[First_Reminder_Type], src.[Second_Reminder_Type], src.[First_Reminder_Sent_At], src.[Second_Reminder_Sent_At], src.[Latest_Reminder_Type], src.[Last_Reminded_At], src.[Times_Contacted], src.[Run_Date], src.[Site_Id], src.[Recall_Type], src.[Due_Date], src.[Interval_Months], src.[Status], src.[Sent_At], src.[Booked_At], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Recalls] AS tgt WHERE tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Recalls] AS tgt
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