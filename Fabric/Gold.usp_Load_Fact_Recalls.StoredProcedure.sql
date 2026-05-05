--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Recalls
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Recalls @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Recalls]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Recalls]
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
            r.Tenant_ID                                                     AS Tenant_ID,
            r.Id                                                            AS bk_Recall_ID,
            ISNULL(dpat.pk_Patient, -1)                                     AS fk_Patient,
            dd_due.pk_Date                                                  AS fk_Date_Due,
            dd_run.pk_Date                                                  AS fk_Date_Run,
            dd_fr.pk_Date                                                   AS fk_Date_First_Reminder,
            dd_sr.pk_Date                                                   AS fk_Date_Second_Reminder,
            dd_lr.pk_Date                                                   AS fk_Date_Last_Reminded,
            NULLIF(TRIM(r.Appointment_ID),'')                               AS Appointment_ID,
            NULLIF(TRIM(r.Recall_Type),'')                                  AS Recall_Type,
            NULLIF(TRIM(r.Recall_Method),'')                                AS Recall_Method,
            NULLIF(TRIM(r.Status),'')                                       AS Status,
            NULLIF(TRIM(r.Workflow_Status),'')                              AS Workflow_Status,
            NULLIF(TRIM(r.Workflow_Stage_ID),'')                            AS Workflow_Stage_ID,
            NULLIF(TRIM(r.First_Reminder_Type),'')                          AS First_Reminder_Type,
            NULLIF(TRIM(r.Second_Reminder_Type),'')                         AS Second_Reminder_Type,
            NULLIF(TRIM(r.Latest_Reminder_Type),'')                         AS Latest_Reminder_Type,
            CAST(ISNULL(r.Times_Contacted,0) AS INT)                        AS Times_Contacted,
            CAST(r.Due_Date AS DATE)                                        AS Due_Date,
            TRY_CAST(r.Run_Date AS DATE)                                    AS Run_Date,
            CASE WHEN r.Due_Date IS NOT NULL
                      AND NULLIF(TRIM(r.Status),'') NOT IN ('booked','completed')
                 THEN DATEDIFF(DAY, r.Due_Date, CAST(SYSUTCDATETIME() AS DATE))
            END                                                             AS Days_Overdue
        INTO #src
        FROM Silver.Recalls r
        LEFT JOIN Gold.Dim_Patients dpat  ON dpat.Patient_ID  = CAST(r.Patient_Id AS INT) AND dpat.Tenant_ID = r.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_due    ON dd_due.Full_Date = CAST(r.Due_Date AS DATE)
        LEFT JOIN Gold.Dim_Date dd_run    ON dd_run.Full_Date = TRY_CAST(r.Run_Date AS DATE)
        LEFT JOIN Gold.Dim_Date dd_fr     ON dd_fr.Full_Date  = TRY_CAST(NULLIF(TRIM(r.First_Reminder_Sent_At),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_sr     ON dd_sr.Full_Date  = TRY_CAST(NULLIF(TRIM(r.Second_Reminder_Sent_At),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_lr     ON dd_lr.Full_Date  = TRY_CAST(NULLIF(TRIM(r.Last_Reminded_At),'') AS DATE)
        WHERE r.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Recalls tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Recall_ID = tgt.bk_Recall_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient               = src.fk_Patient,
            fk_Date_Due              = src.fk_Date_Due,
            fk_Date_Run              = src.fk_Date_Run,
            fk_Date_First_Reminder   = src.fk_Date_First_Reminder,
            fk_Date_Second_Reminder  = src.fk_Date_Second_Reminder,
            fk_Date_Last_Reminded    = src.fk_Date_Last_Reminded,
            Appointment_ID           = src.Appointment_ID,
            Recall_Type              = src.Recall_Type,
            Recall_Method            = src.Recall_Method,
            Status                   = src.Status,
            Workflow_Status          = src.Workflow_Status,
            Workflow_Stage_ID        = src.Workflow_Stage_ID,
            First_Reminder_Type      = src.First_Reminder_Type,
            Second_Reminder_Type     = src.Second_Reminder_Type,
            Latest_Reminder_Type     = src.Latest_Reminder_Type,
            Times_Contacted          = src.Times_Contacted,
            Due_Date                 = src.Due_Date,
            Run_Date                 = src.Run_Date,
            Days_Overdue             = src.Days_Overdue,
            DW_Updated_At            = SYSUTCDATETIME()
        FROM Gold.Fact_Recalls tgt
        INNER JOIN #src src ON tgt.bk_Recall_ID = src.bk_Recall_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Due] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Run] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_First_Reminder] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Second_Reminder] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Last_Reminded] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Workflow_Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Workflow_Stage_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Reminder_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Second_Reminder_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Latest_Reminder_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Times_Contacted] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Due_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Run_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Days_Overdue] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Due] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Run] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_First_Reminder] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Second_Reminder] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Last_Reminded] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Workflow_Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Workflow_Stage_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Reminder_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Second_Reminder_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Latest_Reminder_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Times_Contacted] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Due_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Run_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Days_Overdue] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Recalls (
            Tenant_ID,
            bk_Recall_ID,
            fk_Patient, fk_Date_Due, fk_Date_Run,
            fk_Date_First_Reminder, fk_Date_Second_Reminder, fk_Date_Last_Reminded,
            Appointment_ID, Recall_Type, Recall_Method, Status, Workflow_Status, Workflow_Stage_ID,
            First_Reminder_Type, Second_Reminder_Type, Latest_Reminder_Type,
            Times_Contacted, Due_Date, Run_Date, Days_Overdue,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Recall_ID,
            src.fk_Patient, src.fk_Date_Due, src.fk_Date_Run,
            src.fk_Date_First_Reminder, src.fk_Date_Second_Reminder, src.fk_Date_Last_Reminded,
            src.Appointment_ID, src.Recall_Type, src.Recall_Method, src.Status, src.Workflow_Status, src.Workflow_Stage_ID,
            src.First_Reminder_Type, src.Second_Reminder_Type, src.Latest_Reminder_Type,
            src.Times_Contacted, src.Due_Date, src.Run_Date, src.Days_Overdue,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Recalls tgt WHERE tgt.bk_Recall_ID = src.bk_Recall_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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
