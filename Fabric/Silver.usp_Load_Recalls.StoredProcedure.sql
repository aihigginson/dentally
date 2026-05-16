--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Recalls] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Recalls
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     15/05/2026  AIH Align with rebuilt Bronze schema: Recall_Date->Due_Date,
--                            Interval_Months, Site_Id, Practitioner_Id from Bronze;
--                            legacy API columns (Appointment_ID, Workflow_* etc.) set to NULL
--  To Run           :   DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Silver.usp_Load_Recalls @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
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
        ISNULL(CAST(staged.[Patient_Id]      AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id]         AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Recall_Type]     AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Due_Date]        AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Interval_Months] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status]          AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [Id],
                TRY_CAST(ROUND(CAST(Patient_ID      AS float), 0) AS int)  AS [Patient_Id],
                TRY_CAST(ROUND(CAST(Practitioner_ID AS float), 0) AS int)  AS [Practitioner_Id],
                NULL  AS [Appointment_ID],
                NULL  AS [Recall_Method],
                NULL  AS [Workflow_Status],
                NULL  AS [Workflow_Stage_ID],
                NULL  AS [First_Reminder_Type],
                NULL  AS [Second_Reminder_Type],
                NULL  AS [First_Reminder_Sent_At],
                NULL  AS [Second_Reminder_Sent_At],
                NULL  AS [Latest_Reminder_Type],
                NULL  AS [Last_Reminded_At],
                NULL  AS [Times_Contacted],
                NULL  AS [Run_Date],
                LEFT(Site_ID, 50)    AS [Site_Id],
                LEFT(Recall_Type, 50)  AS [Recall_Type],
                TRY_CAST(Recall_Date AS date)  AS [Due_Date],
                TRY_CAST(ROUND(CAST(Interval_Months AS float), 0) AS int)  AS [Interval_Months],
                LEFT(Status, 50)  AS [Status],
                CAST(NULL AS datetime2(3))  AS [Sent_At],
                CAST(NULL AS datetime2(3))  AS [Booked_At]
            FROM Bronze.Recalls
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_Id]              = src.[Patient_Id],
            [Practitioner_Id]         = src.[Practitioner_Id],
            [Appointment_ID]          = src.[Appointment_ID],
            [Recall_Method]           = src.[Recall_Method],
            [Workflow_Status]         = src.[Workflow_Status],
            [Workflow_Stage_ID]       = src.[Workflow_Stage_ID],
            [First_Reminder_Type]     = src.[First_Reminder_Type],
            [Second_Reminder_Type]    = src.[Second_Reminder_Type],
            [First_Reminder_Sent_At]  = src.[First_Reminder_Sent_At],
            [Second_Reminder_Sent_At] = src.[Second_Reminder_Sent_At],
            [Latest_Reminder_Type]    = src.[Latest_Reminder_Type],
            [Last_Reminded_At]        = src.[Last_Reminded_At],
            [Times_Contacted]         = src.[Times_Contacted],
            [Run_Date]                = src.[Run_Date],
            [Site_Id]                 = src.[Site_Id],
            [Recall_Type]             = src.[Recall_Type],
            [Due_Date]                = src.[Due_Date],
            [Interval_Months]         = src.[Interval_Months],
            [Status]                  = src.[Status],
            [Sent_At]                 = src.[Sent_At],
            [Booked_At]               = src.[Booked_At],
            [DW_Updated_At]           = SYSUTCDATETIME(),
            [_Row_Hash]               = src._Hash,
            [_Raw_Json]               = NULL
        FROM [Silver].[Recalls] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Recalls] (
            [Tenant_ID], [Id], [Patient_Id], [Practitioner_Id], [Appointment_ID],
            [Recall_Method], [Workflow_Status], [Workflow_Stage_ID],
            [First_Reminder_Type], [Second_Reminder_Type],
            [First_Reminder_Sent_At], [Second_Reminder_Sent_At],
            [Latest_Reminder_Type], [Last_Reminded_At], [Times_Contacted], [Run_Date],
            [Site_Id], [Recall_Type], [Due_Date], [Interval_Months], [Status],
            [Sent_At], [Booked_At],
            [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json]
        )
        SELECT
            src.[Tenant_ID], src.[Id], src.[Patient_Id], src.[Practitioner_Id], src.[Appointment_ID],
            src.[Recall_Method], src.[Workflow_Status], src.[Workflow_Stage_ID],
            src.[First_Reminder_Type], src.[Second_Reminder_Type],
            src.[First_Reminder_Sent_At], src.[Second_Reminder_Sent_At],
            src.[Latest_Reminder_Type], src.[Last_Reminded_At], src.[Times_Contacted], src.[Run_Date],
            src.[Site_Id], src.[Recall_Type], src.[Due_Date], src.[Interval_Months], src.[Status],
            src.[Sent_At], src.[Booked_At],
            SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Recalls] AS tgt
            WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Recalls] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src
            WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Id] = tgt.[Id]
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
