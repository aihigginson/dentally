--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Invoice_Items] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Invoice_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01..*08  (see git history) -- incremental 2-source watermark delta build.
--    *09     20/06/2026  AIH GRAIN SPLIT: invoice header amounts/attrs removed from the
--                            line fact (they now live on Gold.Fact_Invoices /
--                            Gold.Dim_Invoices). Dropped Invoice_Amount/_Outstanding/_NHS,
--                            Is_Invoice_Outstanding, Invoice_Reference/Payment_Terms/Footnote/
--                            Invoice_Paid and fk_Date_Due/Paid. Added fk_Invoice (-> Dim_Invoices).
--                            Invoice_Discount rebuild moved to usp_Load_Dim_Invoices. Header is
--                            still joined for the line's patient/account/site/invoice-date context.
--    *10     20/06/2026  AIH Added fk_Treatment: resolved line -> Silver.Treatment_Plan_Items
--                            (Treatment_Plan_Item_ID -> Id, carries Treatment_ID) ->
--                            Gold.Dim_Treatments. Sundry lines -> -1. Folded into V018.
--                            Also: Treatment_Plan_Item_ID column bigint -> VARCHAR(50) storing the
--                            RAW key (was TRY_CAST AS INT -> NULL for GUID ids -> silently broke
--                            KPI_Snapshot 'charged'/open-courses detection). Now stores the GUID
--                            so KPI_Snapshot's bk_Treatment_Plan_Item_ID join works for all data.
--  To Run			 :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Invoice_Items @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Invoice_Items]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Invoice_Items]
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

        -- Incremental 2-source watermark: process only lines whose line (ii) OR invoice
        -- header (inv) changed since the last successful load. The header is still joined
        -- for the line's patient/account/site/invoice-date context (and fk_Invoice), but
        -- the invoice AMOUNTS/attributes are no longer selected (they live on Fact_Invoices
        -- / Dim_Invoices). Missing watermark (first run) or @Full_Reload = 1 -> full load.
        DECLARE @Run_Start datetime2(3) = SYSUTCDATETIME();
        DECLARE @Watermark datetime2(3) =
            CASE WHEN @Full_Reload = 1 THEN CONVERT(datetime2(3), '1900-01-01')
                 ELSE ISNULL((SELECT Last_Loaded_At FROM Gold.Load_Watermark
                              WHERE Entity_Name = 'Fact_Invoice_Items'),
                             CONVERT(datetime2(3), '1900-01-01'))
            END;

        -- Safety net: if the fact table is EMPTY (e.g. a release just DROP/CREATE'd it), the stale
        -- Load_Watermark would make the incremental reload only recently-changed rows and silently
        -- under-load the table. An empty table => ignore the watermark and full-load.
        IF NOT EXISTS (SELECT 1 FROM Gold.Fact_Invoice_Items)
            SET @Watermark = CONVERT(datetime2(3), '1900-01-01');

        SELECT
            ii.Tenant_ID                                                AS Tenant_ID,
            ii.Id                                                       AS bk_Invoice_Item_ID,
            ISNULL(dinv.pk_Invoice, -1)                                 AS fk_Invoice,
            ISNULL(dpat.pk_Patient, -1)                                 AS fk_Patient,
            ISNULL(dpr.pk_Practitioner, -1)                             AS fk_Practitioner,
            ISNULL(dpp.pk_Payment_Plan, -1)                             AS fk_Payment_Plan,
            ISNULL(dtp.pk_Treatment_Plan, -1)                           AS fk_Treatment_Plan,
            ISNULL(dt.pk_Treatment, -1)                                 AS fk_Treatment,
            ISNULL(dps.pk_Practice_Site, -1)                            AS fk_Practice_Site,
            ISNULL(du.pk_User, -1)                                      AS fk_User,
            dd_inv.pk_Date                                              AS fk_Date_Invoice,
            dd_c.pk_Date                                                AS fk_Date_Created,
            CAST(ii.Invoice_ID AS INT)                                  AS Invoice_ID,
            NULLIF(TRIM(ii.Treatment_Plan_Item_ID),'')                  AS Treatment_Plan_Item_ID,
            NULLIF(TRIM(ii.Sundry_ID),'')                               AS Sundry_ID,
            NULLIF(TRIM(ii.Name),'')                                    AS Item_Name,
            CAST(ISNULL(ii.Item_Price,0) AS DECIMAL(12,2))              AS Item_Price,
            CAST(ISNULL(ii.Quantity,0) AS DECIMAL(10,4))                AS Quantity,
            CAST(ISNULL(ii.Total_Price,0) AS DECIMAL(12,2))             AS Total_Price,
            CAST(ISNULL(ii.NHS_Charge,0) AS DECIMAL(12,2))              AS NHS_Charge
        INTO #src
        FROM Silver.Invoice_Items ii
        LEFT JOIN Silver.Invoices inv         ON inv.Id              = ii.Invoice_ID        AND inv.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Invoices dinv      ON dinv.bk_Invoice_ID  = CAST(ii.Invoice_ID AS INT)        AND dinv.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Patients dpat      ON dpat.Patient_ID     = CAST(inv.Patient_ID AS INT)      AND dpat.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dpr  ON dpr.Practitioner_ID = CAST(ii.Practitioner_ID AS INT)  AND dpr.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Payment_Plans dpp  ON dpp.Payment_Plan_ID = (
                                                    SELECT TOP 1 Payment_Plan_ID
                                                    FROM Silver.Patients
                                                    WHERE Patient_ID = inv.Patient_ID
                                                      AND Tenant_ID  = ii.Tenant_ID)                   AND dpp.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Treatment_Plans dtp ON dtp.Treatment_Plan_ID = CAST(ii.Treatment_Plan_ID AS INT) AND dtp.Tenant_ID = ii.Tenant_ID
        -- Resolve the line's treatment via its treatment-plan-item: invoice line ->
        -- Silver.Treatment_Plan_Items (carries Treatment_ID) -> Gold.Dim_Treatments.
        -- Sundry lines (no treatment-plan-item) fall through to fk_Treatment = -1.
        LEFT JOIN Silver.Treatment_Plan_Items tpi ON tpi.Id            = ii.Treatment_Plan_Item_ID AND tpi.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Treatments dt       ON dt.Treatment_ID      = tpi.Treatment_ID          AND dt.Tenant_ID  = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites dps  ON dps.Site_ID           = NULLIF(TRIM(inv.Site_ID),'')  AND dps.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Users du            ON du.bk_User_ID         = TRY_CAST(NULLIF(TRIM(ii.User_ID),'') AS INT) AND du.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_inv         ON dd_inv.Full_Date      = CAST(inv.Dated_On AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c           ON dd_c.Full_Date        = TRY_CAST(NULLIF(TRIM(ii.Created_At),'') AS DATE)
        WHERE ii.Id IS NOT NULL
          AND (ii.DW_Updated_At > @Watermark OR inv.DW_Updated_At > @Watermark);  -- 2-source delta: line OR header changed

        -- Remove rows no longer in source (#src is a DELTA; orphan detect vs FULL Silver).
        DELETE tgt
        FROM Gold.Fact_Invoice_Items tgt
        WHERE NOT EXISTS (SELECT 1 FROM Silver.Invoice_Items s
                          WHERE s.Id = tgt.bk_Invoice_Item_ID AND s.Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Invoice               = src.fk_Invoice,
            fk_Patient               = src.fk_Patient,
            fk_Practitioner          = src.fk_Practitioner,
            fk_Payment_Plan          = src.fk_Payment_Plan,
            fk_Treatment_Plan        = src.fk_Treatment_Plan,
            fk_Treatment             = src.fk_Treatment,
            fk_Practice_Site         = src.fk_Practice_Site,
            fk_User                  = src.fk_User,
            fk_Date_Invoice          = src.fk_Date_Invoice,
            fk_Date_Created          = src.fk_Date_Created,
            Invoice_ID               = src.Invoice_ID,
            Treatment_Plan_Item_ID   = src.Treatment_Plan_Item_ID,
            Sundry_ID                = src.Sundry_ID,
            Item_Name                = src.Item_Name,
            Item_Price               = src.Item_Price,
            Quantity                 = src.Quantity,
            Total_Price              = src.Total_Price,
            NHS_Charge               = src.NHS_Charge,
            DW_Updated_At            = SYSUTCDATETIME()
        FROM Gold.Fact_Invoice_Items tgt
        INNER JOIN #src src ON tgt.bk_Invoice_Item_ID = src.bk_Invoice_Item_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Invoice]             AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Patient]             AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Payment_Plan]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment_Plan]      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site]       AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_User]                AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Invoice]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_ID]             AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Plan_Item_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Sundry_ID]              AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Item_Name]              AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Item_Price]             AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Quantity]               AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Price]            AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Charge]             AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Invoice]             AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Patient]             AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Payment_Plan]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment_Plan]      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site]       AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_User]                AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Invoice]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_ID]             AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Plan_Item_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Sundry_ID]              AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Item_Name]              AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Item_Price]             AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Quantity]               AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Price]            AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Charge]             AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Invoice_Items (
            Tenant_ID, bk_Invoice_Item_ID, fk_Invoice,
            fk_Patient, fk_Practitioner, fk_Payment_Plan, fk_Treatment_Plan, fk_Treatment,
            fk_Practice_Site, fk_User,
            fk_Date_Invoice, fk_Date_Created,
            Invoice_ID, Treatment_Plan_Item_ID, Sundry_ID, Item_Name,
            Item_Price, Quantity, Total_Price, NHS_Charge,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_Invoice_Item_ID, src.fk_Invoice,
            src.fk_Patient, src.fk_Practitioner, src.fk_Payment_Plan, src.fk_Treatment_Plan, src.fk_Treatment,
            src.fk_Practice_Site, src.fk_User,
            src.fk_Date_Invoice, src.fk_Date_Created,
            src.Invoice_ID, src.Treatment_Plan_Item_ID, src.Sundry_ID, src.Item_Name,
            src.Item_Price, src.Quantity, src.Total_Price, src.NHS_Charge,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Invoice_Items tgt WHERE tgt.bk_Invoice_Item_ID = src.bk_Invoice_Item_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        -- Advance the watermark only after a successful load (inside TRY).
        UPDATE Gold.Load_Watermark
           SET Last_Loaded_At = @Run_Start, DW_Updated_At = SYSUTCDATETIME()
         WHERE Entity_Name = 'Fact_Invoice_Items';
        IF @@ROWCOUNT = 0
            INSERT INTO Gold.Load_Watermark (Entity_Name, Last_Loaded_At, DW_Updated_At)
            VALUES ('Fact_Invoice_Items', @Run_Start, SYSUTCDATETIME());

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
