/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Treatment_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Treatment_Appointments]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Treatment_Appointments]
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
            ta.Id                                                       AS bk_Treatment_Appointment_ID,
            dpat.pk_Patient                                             AS fk_Patient,
            dtp.pk_Treatment_Plan                                       AS fk_Treatment_Plan,
            dd_a.pk_Date                                                AS fk_Date_Appointment,
            dd_c.pk_Date                                                AS fk_Date_Created,
            ta.Appointment_Id                                           AS Appointment_ID,
            ta.Treatment_Plan_Id                                        AS Treatment_Plan_ID,
            ta.Position                                                 AS Position,
            ta.Bookable                                                 AS Bookable,
            NULLIF(TRIM(ta.Notes),'')                                   AS Notes,
            CAST(NULL AS datetime2(3))                                  AS Created_At,
            CAST(NULL AS datetime2(3))                                  AS Updated_At
        INTO #src
        FROM Silver.Treatment_Appointments ta
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID        = ta.Patient_Id
        LEFT JOIN Gold.Dim_Treatment_Plans dtp  ON dtp.Treatment_Plan_ID  = ta.Treatment_Plan_Id
        LEFT JOIN Silver.Appointments ba        ON ba.Appointment_Id      = ta.Appointment_Id
        LEFT JOIN Gold.Dim_Date dd_a            ON dd_a.Full_Date         = TRY_CAST(NULLIF(TRIM(ba.Start_Time),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c            ON dd_c.Full_Date         = TRY_CAST(NULLIF(TRIM(ba.Start_Time),'') AS DATE)
        WHERE ta.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Treatment_Appointments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Treatment_Appointment_ID = tgt.bk_Treatment_Appointment_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient              = src.fk_Patient,
            fk_Treatment_Plan       = src.fk_Treatment_Plan,
            fk_Date_Appointment     = src.fk_Date_Appointment,
            fk_Date_Created         = src.fk_Date_Created,
            Appointment_ID          = src.Appointment_ID,
            Treatment_Plan_ID       = src.Treatment_Plan_ID,
            Position                = src.Position,
            Bookable                = src.Bookable,
            Notes                   = src.Notes,
            Updated_At              = src.Updated_At,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Treatment_Appointments tgt
        INNER JOIN #src src ON tgt.bk_Treatment_Appointment_ID = src.bk_Treatment_Appointment_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Appointment] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Position] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Bookable] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_At] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Appointment] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Position] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Bookable] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_At] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Treatment_Appointments (
            bk_Treatment_Appointment_ID,
            fk_Patient, fk_Treatment_Plan,
            fk_Date_Appointment, fk_Date_Created,
            Appointment_ID, Treatment_Plan_ID, Position, Bookable, Notes,
            Created_At, Updated_At, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.bk_Treatment_Appointment_ID,
            src.fk_Patient, src.fk_Treatment_Plan,
            src.fk_Date_Appointment, src.fk_Date_Created,
            src.Appointment_ID, src.Treatment_Plan_ID, src.Position, src.Bookable, src.Notes,
            src.Created_At, src.Updated_At, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Treatment_Appointments tgt WHERE tgt.bk_Treatment_Appointment_ID = src.bk_Treatment_Appointment_ID);
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
