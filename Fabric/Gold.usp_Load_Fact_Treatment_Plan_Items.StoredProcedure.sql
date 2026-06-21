--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Treatment_Plan_Items] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Treatment_Plan_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--    *03     19/05/2026  AIH bk_Treatment_Plan_Item_ID: use tpi.Id directly (UUID, not INT)
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *05     14/06/2026  AIH Incremental (watermark) delta load. Clean single-source fact
--                            (Silver.Treatment_Plan_Items + stable dim pks), delta == full refresh.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Treatment_Plan_Items @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Treatment_Plan_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Treatment_Plan_Items]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Treatment_Plan_Items]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
    , @Full_Reload   BIT = 0
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

        -- Incremental watermark: process only Silver plan-items changed since the
        -- last successful load (DW_Updated_At is hash-gated -> exact delta). Missing
        -- watermark (first run) or @Full_Reload = 1 -> full load.
        DECLARE @Run_Start datetime2(3) = SYSUTCDATETIME();
        DECLARE @Watermark datetime2(3) =
            CASE WHEN @Full_Reload = 1 THEN CONVERT(datetime2(3), '1900-01-01')
                 ELSE ISNULL((SELECT Last_Loaded_At FROM Gold.Load_Watermark
                              WHERE Entity_Name = 'Fact_Treatment_Plan_Items'),
                             CONVERT(datetime2(3), '1900-01-01'))
            END;

        SELECT
            tpi.Tenant_ID                                                   AS Tenant_ID,
            tpi.Id                                                          AS bk_Treatment_Plan_Item_ID,
            ISNULL(dp.pk_Treatment_Plan, -1)                                AS fk_Treatment_Plan,
            ISNULL(dpat.pk_Patient, -1)                                     AS fk_Patient,
            ISNULL(dpr.pk_Practitioner, -1)                                 AS fk_Practitioner,
            ISNULL(dpp.pk_Payment_Plan, -1)                                 AS fk_Payment_Plan,
            ISNULL(dt.pk_Treatment, -1)                                     AS fk_Treatment,
            dd_c.pk_Date                                                    AS fk_Date_Created,
            dd_comp.pk_Date                                                 AS fk_Date_Completed,
            dd_u.pk_Date                                                    AS fk_Date_Updated,
            TRY_CAST(tpi.Treatment_Plan_ID AS INT)                          AS Treatment_Plan_ID,
            TRY_CAST(NULLIF(TRIM(tpi.Invoice_ID),'') AS INT)                AS Invoice_ID,
            NULLIF(TRIM(tpi.Treatment_Appointment_ID),'')                   AS Treatment_Appointment_ID,
            TRY_CAST(NULLIF(TRIM(tpi.Referrer_ID),'') AS INT)              AS Referrer_ID,
            NULLIF(TRIM(tpi.Nomenclature),'')                               AS Nomenclature,
            NULLIF(TRIM(tpi.NHS_Treatment_Cat),'')                          AS NHS_Treatment_Cat,
            NULLIF(TRIM(tpi.UDA_Band),'')                                   AS UDA_Band,
            NULLIF(TRIM(tpi.Region),'')                                     AS Region,
            CAST(tpi.Position AS INT)                                       AS Position,
            CAST(ISNULL(tpi.Base_Chart,0) AS BIT)                           AS Base_Chart,
            CAST(ISNULL(tpi.Completed,0) AS BIT)                            AS Completed,
            CAST(ISNULL(tpi.Charged,0) AS BIT)                              AS Charged,
            CAST(ISNULL(tpi.Appear_On_Invoice,0) AS BIT)                    AS Appear_On_Invoice,
            CAST(ISNULL(tpi.Price,0) AS DECIMAL(12,2))                      AS Price,
            CAST(tpi.Duration AS INT)                                       AS Duration_Mins
        INTO #src
        FROM Silver.Treatment_Plan_Items tpi
        LEFT JOIN Gold.Dim_Treatment_Plans dp   ON dp.Treatment_Plan_ID  = TRY_CAST(tpi.Treatment_Plan_ID AS INT) AND dp.Tenant_ID = tpi.Tenant_ID
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID       = TRY_CAST(tpi.Patient_ID AS INT)        AND dpat.Tenant_ID = tpi.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dpr    ON dpr.Practitioner_ID   = TRY_CAST(tpi.Practitioner_ID AS INT)   AND dpr.Tenant_ID = tpi.Tenant_ID
        LEFT JOIN Gold.Dim_Payment_Plans dpp    ON dpp.Payment_Plan_ID   = TRY_CAST(tpi.Payment_Plan_ID AS INT)   AND dpp.Tenant_ID = tpi.Tenant_ID
        LEFT JOIN Gold.Dim_Treatments dt        ON dt.Treatment_ID       = TRY_CAST(tpi.Treatment_ID AS INT)      AND dt.Tenant_ID = tpi.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_c            ON dd_c.Full_Date        = TRY_CAST(NULLIF(TRIM(tpi.Created_At),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_comp         ON dd_comp.Full_Date     = TRY_CAST(NULLIF(TRIM(tpi.Completed_At),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_u            ON dd_u.Full_Date        = TRY_CAST(NULLIF(TRIM(tpi.Updated_At),'') AS DATE)
        WHERE tpi.Id IS NOT NULL
          AND tpi.DW_Updated_At > @Watermark;   -- delta: only changed/new plan-items

        -- Remove rows no longer in source. #src is now a DELTA, so orphan detection
        -- runs against the FULL Silver key set (keys only -- cheap).
        DELETE tgt
        FROM Gold.Fact_Treatment_Plan_Items tgt
        WHERE NOT EXISTS (SELECT 1 FROM Silver.Treatment_Plan_Items s
                          WHERE s.Id = tgt.bk_Treatment_Plan_Item_ID AND s.Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Treatment_Plan        = src.fk_Treatment_Plan,
            fk_Patient               = src.fk_Patient,
            fk_Practitioner          = src.fk_Practitioner,
            fk_Payment_Plan          = src.fk_Payment_Plan,
            fk_Treatment             = src.fk_Treatment,
            fk_Date_Created          = src.fk_Date_Created,
            fk_Date_Completed        = src.fk_Date_Completed,
            fk_Date_Updated          = src.fk_Date_Updated,
            Invoice_ID               = src.Invoice_ID,
            Treatment_Appointment_ID = src.Treatment_Appointment_ID,
            Nomenclature             = src.Nomenclature,
            NHS_Treatment_Cat        = src.NHS_Treatment_Cat,
            UDA_Band                 = src.UDA_Band,
            Region                   = src.Region,
            Completed                = src.Completed,
            Charged                  = src.Charged,
            Appear_On_Invoice        = src.Appear_On_Invoice,
            Price                    = src.Price,
            Duration_Mins            = src.Duration_Mins,
            DW_Updated_At            = SYSUTCDATETIME()
        FROM Gold.Fact_Treatment_Plan_Items tgt
        INNER JOIN #src src ON tgt.bk_Treatment_Plan_Item_ID = src.bk_Treatment_Plan_Item_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Updated] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Region] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Charged] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appear_On_Invoice] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Price] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Duration_Mins] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Updated] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Region] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Charged] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appear_On_Invoice] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Price] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Duration_Mins] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Treatment_Plan_Items (
            Tenant_ID,
            bk_Treatment_Plan_Item_ID,
            fk_Treatment_Plan, fk_Patient, fk_Practitioner, fk_Payment_Plan, fk_Treatment,
            fk_Date_Created, fk_Date_Completed, fk_Date_Updated,
            Treatment_Plan_ID, Invoice_ID, Treatment_Appointment_ID, Referrer_ID,
            Nomenclature, NHS_Treatment_Cat, UDA_Band, Region,
            Position, Base_Chart, Completed, Charged, Appear_On_Invoice, Price, Duration_Mins,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Treatment_Plan_Item_ID,
            src.fk_Treatment_Plan, src.fk_Patient, src.fk_Practitioner, src.fk_Payment_Plan, src.fk_Treatment,
            src.fk_Date_Created, src.fk_Date_Completed, src.fk_Date_Updated,
            src.Treatment_Plan_ID, src.Invoice_ID, src.Treatment_Appointment_ID, src.Referrer_ID,
            src.Nomenclature, src.NHS_Treatment_Cat, src.UDA_Band, src.Region,
            src.Position, src.Base_Chart, src.Completed, src.Charged, src.Appear_On_Invoice, src.Price, src.Duration_Mins,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Treatment_Plan_Items tgt WHERE tgt.bk_Treatment_Plan_Item_ID = src.bk_Treatment_Plan_Item_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        -- Advance the watermark only after a successful load (inside TRY).
        UPDATE Gold.Load_Watermark
           SET Last_Loaded_At = @Run_Start, DW_Updated_At = SYSUTCDATETIME()
         WHERE Entity_Name = 'Fact_Treatment_Plan_Items';
        IF @@ROWCOUNT = 0
            INSERT INTO Gold.Load_Watermark (Entity_Name, Last_Loaded_At, DW_Updated_At)
            VALUES ('Fact_Treatment_Plan_Items', @Run_Start, SYSUTCDATETIME());

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
