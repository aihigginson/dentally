--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Invoices] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Invoices
--  Author           :  AIH
--  Initital Date    :  20/06/2026
--  History          :
--    *01     20/06/2026  AIH Initial release. Invoice-grain fact (1/invoice) holding the
--                            additive invoice amounts previously folded onto Fact_Invoice_Items.
--                            Incremental single-source watermark delta on Silver.Invoices
--                            (mirrors Gold.usp_Load_Fact_Invoice_Items). fk_Invoice resolved
--                            via Gold.Dim_Invoices.
--  To Run			 :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Invoices @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Invoices]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Invoices]
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

        -- Incremental single-source watermark: process only invoices whose header
        -- changed since the last successful load. Missing watermark (first run) or
        -- @Full_Reload = 1 -> full load.
        DECLARE @Run_Start datetime2(3) = SYSUTCDATETIME();
        DECLARE @Watermark datetime2(3) =
            CASE WHEN @Full_Reload = 1 THEN CONVERT(datetime2(3), '1900-01-01')
                 ELSE ISNULL((SELECT Last_Loaded_At FROM Gold.Load_Watermark
                              WHERE Entity_Name = 'Fact_Invoices'),
                             CONVERT(datetime2(3), '1900-01-01'))
            END;

        SELECT
            inv.Tenant_ID                                              AS Tenant_ID,
            CAST(inv.Id AS INT)                                        AS bk_Invoice_ID,
            ISNULL(dinv.pk_Invoice, -1)                               AS fk_Invoice,
            ISNULL(dpat.pk_Patient, -1)                               AS fk_Patient,
            ISNULL(dacc.pk_Account, -1)                               AS fk_Account,
            ISNULL(dps.pk_Practice_Site, -1)                          AS fk_Practice_Site,
            ISNULL(du.pk_User, -1)                                    AS fk_User,
            dd_inv.pk_Date                                            AS fk_Date_Invoice,
            dd_due.pk_Date                                            AS fk_Date_Due,
            dd_paid.pk_Date                                           AS fk_Date_Paid,
            CAST(ISNULL(inv.Amount,0) AS DECIMAL(12,2))               AS Invoice_Amount,
            CAST(ISNULL(inv.Amount_Outstanding,0) AS DECIMAL(12,2))   AS Invoice_Amount_Outstanding,
            CAST(TRY_CAST(inv.NHS_Amount AS DECIMAL(12,2)) AS DECIMAL(12,2)) AS Invoice_NHS_Amount,
            CASE WHEN CAST(ISNULL(inv.Amount_Outstanding,0) AS DECIMAL(12,2)) > 0 THEN 1 ELSE 0 END AS Is_Invoice_Outstanding
        INTO #src
        FROM Silver.Invoices inv
        LEFT JOIN Gold.Dim_Invoices dinv      ON dinv.bk_Invoice_ID  = CAST(inv.Id AS INT)         AND dinv.Tenant_ID = inv.Tenant_ID
        LEFT JOIN Gold.Dim_Patients dpat      ON dpat.Patient_ID     = CAST(inv.Patient_ID AS INT) AND dpat.Tenant_ID = inv.Tenant_ID
        LEFT JOIN Gold.Dim_Accounts dacc      ON dacc.Account_ID     = CAST(inv.Account_ID AS INT) AND dacc.Tenant_ID = inv.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites dps ON dps.Site_ID         = NULLIF(TRIM(inv.Site_ID),'') AND dps.Tenant_ID = inv.Tenant_ID
        LEFT JOIN Gold.Dim_Users du           ON du.bk_User_ID       = TRY_CAST(NULLIF(TRIM(inv.User_ID),'') AS INT) AND du.Tenant_ID = inv.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_inv        ON dd_inv.Full_Date    = CAST(inv.Dated_On AS DATE)
        LEFT JOIN Gold.Dim_Date dd_due        ON dd_due.Full_Date    = CAST(inv.Due_On AS DATE)
        LEFT JOIN Gold.Dim_Date dd_paid       ON dd_paid.Full_Date   = CAST(inv.Paid_On AS DATE)
        WHERE inv.Id IS NOT NULL
          AND inv.DW_Updated_At > @Watermark;

        -- Remove rows no longer in source (key-only anti-join vs full Silver)
        DELETE tgt
        FROM Gold.Fact_Invoices tgt
        WHERE NOT EXISTS (SELECT 1 FROM Silver.Invoices s
                          WHERE CAST(s.Id AS INT) = tgt.bk_Invoice_ID AND s.Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Invoice                 = src.fk_Invoice,
            fk_Patient                 = src.fk_Patient,
            fk_Account                 = src.fk_Account,
            fk_Practice_Site           = src.fk_Practice_Site,
            fk_User                    = src.fk_User,
            fk_Date_Invoice            = src.fk_Date_Invoice,
            fk_Date_Due                = src.fk_Date_Due,
            fk_Date_Paid               = src.fk_Date_Paid,
            Invoice_Amount             = src.Invoice_Amount,
            Invoice_Amount_Outstanding = src.Invoice_Amount_Outstanding,
            Invoice_NHS_Amount         = src.Invoice_NHS_Amount,
            Is_Invoice_Outstanding     = src.Is_Invoice_Outstanding,
            DW_Updated_At              = SYSUTCDATETIME()
        FROM Gold.Fact_Invoices tgt
        INNER JOIN #src src ON tgt.bk_Invoice_ID = src.bk_Invoice_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Invoice]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Patient]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Account]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_User]                    AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Invoice]            AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Due]                AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Paid]               AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Amount]             AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Amount_Outstanding] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_NHS_Amount]         AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Invoice_Outstanding]     AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Invoice]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Patient]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Account]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_User]                    AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Invoice]            AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Due]                AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Paid]               AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Amount]             AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Amount_Outstanding] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_NHS_Amount]         AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Invoice_Outstanding]     AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Invoices (
            Tenant_ID, bk_Invoice_ID, fk_Invoice, fk_Patient, fk_Account,
            fk_Practice_Site, fk_User, fk_Date_Invoice, fk_Date_Due, fk_Date_Paid,
            Invoice_Amount, Invoice_Amount_Outstanding, Invoice_NHS_Amount, Is_Invoice_Outstanding,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_Invoice_ID, src.fk_Invoice, src.fk_Patient, src.fk_Account,
            src.fk_Practice_Site, src.fk_User, src.fk_Date_Invoice, src.fk_Date_Due, src.fk_Date_Paid,
            src.Invoice_Amount, src.Invoice_Amount_Outstanding, src.Invoice_NHS_Amount, src.Is_Invoice_Outstanding,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Invoices tgt
                          WHERE tgt.bk_Invoice_ID = src.bk_Invoice_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        -- Advance the watermark only after a successful load (inside TRY).
        UPDATE Gold.Load_Watermark
           SET Last_Loaded_At = @Run_Start, DW_Updated_At = SYSUTCDATETIME()
         WHERE Entity_Name = 'Fact_Invoices';
        IF @@ROWCOUNT = 0
            INSERT INTO Gold.Load_Watermark (Entity_Name, Last_Loaded_At, DW_Updated_At)
            VALUES ('Fact_Invoices', @Run_Start, SYSUTCDATETIME());

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
