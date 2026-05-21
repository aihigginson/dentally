--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Invoice_Items] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Invoice_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--    *03     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Invoice_Items @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Invoice_Items]    Script Date: 20/04/2026 10:15:06 ******/
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
            ii.Tenant_ID                                                AS Tenant_ID,
            ii.Id                                                       AS bk_Invoice_Item_ID,
            ISNULL(dpat.pk_Patient, -1)                                 AS fk_Patient,
            ISNULL(dpr.pk_Practitioner, -1)                             AS fk_Practitioner,
            ISNULL(dpp.pk_Payment_Plan, -1)                             AS fk_Payment_Plan,
            ISNULL(dtp.pk_Treatment_Plan, -1)                           AS fk_Treatment_Plan,
            ISNULL(dacc.pk_Account, -1)                                 AS fk_Account,
            ISNULL(dps.pk_Practice_Site, -1)                            AS fk_Practice_Site,
            ISNULL(du.pk_User, -1)                                      AS fk_User,
            dd_inv.pk_Date                                              AS fk_Date_Invoice,
            dd_due.pk_Date                                              AS fk_Date_Due,
            dd_paid.pk_Date                                             AS fk_Date_Paid,
            dd_c.pk_Date                                                AS fk_Date_Created,
            CAST(ii.Invoice_ID AS INT)                                  AS Invoice_ID,
            TRY_CAST(ii.Treatment_Plan_Item_ID AS INT)                  AS Treatment_Plan_Item_ID,
            NULLIF(TRIM(ii.Sundry_ID),'')                               AS Sundry_ID,
            NULLIF(TRIM(ii.Name),'')                                    AS Item_Name,
            TRY_CAST(inv.Reference AS INT)                              AS Invoice_Reference,
            NULLIF(TRIM(inv.Payment_Terms),'')                          AS Invoice_Payment_Terms,
            NULLIF(TRIM(inv.Footnote),'')                               AS Invoice_Footnote,
            CAST(ISNULL(inv.Paid,0) AS BIT)                             AS Invoice_Paid,
            CAST(ISNULL(ii.Item_Price,0) AS DECIMAL(12,2))              AS Item_Price,
            CAST(ISNULL(ii.Quantity,0) AS DECIMAL(10,4))                AS Quantity,
            CAST(ISNULL(ii.Total_Price,0) AS DECIMAL(12,2))             AS Total_Price,
            CAST(ISNULL(ii.NHS_Charge,0) AS DECIMAL(12,2))              AS NHS_Charge,
            CAST(ISNULL(inv.Amount,0) AS DECIMAL(12,2))                 AS Invoice_Amount,
            CAST(ISNULL(inv.Amount_Outstanding,0) AS DECIMAL(12,2))     AS Invoice_Amount_Outstanding,
            CAST(TRY_CAST(inv.NHS_Amount AS DECIMAL(12,2)) AS DECIMAL(12,2)) AS Invoice_NHS_Amount
        INTO #src
        FROM Silver.Invoice_Items ii
        LEFT JOIN Silver.Invoices inv         ON inv.Id              = ii.Invoice_ID
        LEFT JOIN Gold.Dim_Patients dpat      ON dpat.Patient_ID     = CAST(inv.Patient_ID AS INT)      AND dpat.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dpr  ON dpr.Practitioner_ID = CAST(ii.Practitioner_ID AS INT)  AND dpr.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Payment_Plans dpp  ON dpp.Payment_Plan_ID = (
                                                    SELECT TOP 1 Payment_Plan_ID
                                                    FROM Silver.Patients
                                                    WHERE Patient_ID = inv.Patient_ID)                  AND dpp.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Treatment_Plans dtp ON dtp.Treatment_Plan_ID = CAST(ii.Treatment_Plan_ID AS INT) AND dtp.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Accounts dacc       ON dacc.Account_ID       = CAST(inv.Account_ID AS INT)   AND dacc.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites dps  ON dps.Site_ID           = NULLIF(TRIM(inv.Site_ID),'')  AND dps.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Users du            ON du.bk_User_ID         = TRY_CAST(NULLIF(TRIM(ii.User_ID),'') AS INT) AND du.Tenant_ID = ii.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_inv         ON dd_inv.Full_Date      = CAST(inv.Dated_On AS DATE)
        LEFT JOIN Gold.Dim_Date dd_due         ON dd_due.Full_Date      = CAST(inv.Due_On AS DATE)
        LEFT JOIN Gold.Dim_Date dd_paid        ON dd_paid.Full_Date     = CAST(inv.Paid_On AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c           ON dd_c.Full_Date        = TRY_CAST(NULLIF(TRIM(ii.Created_At),'') AS DATE)
        WHERE ii.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Invoice_Items tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Invoice_Item_ID = tgt.bk_Invoice_Item_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient               = src.fk_Patient,
            fk_Practitioner          = src.fk_Practitioner,
            fk_Payment_Plan          = src.fk_Payment_Plan,
            fk_Treatment_Plan        = src.fk_Treatment_Plan,
            fk_Account               = src.fk_Account,
            fk_Practice_Site         = src.fk_Practice_Site,
            fk_User                  = src.fk_User,
            fk_Date_Invoice          = src.fk_Date_Invoice,
            fk_Date_Due              = src.fk_Date_Due,
            fk_Date_Paid             = src.fk_Date_Paid,
            fk_Date_Created          = src.fk_Date_Created,
            Item_Name                = src.Item_Name,
            Invoice_Reference        = src.Invoice_Reference,
            Invoice_Payment_Terms    = src.Invoice_Payment_Terms,
            Invoice_Footnote         = src.Invoice_Footnote,
            Invoice_Paid             = src.Invoice_Paid,
            Item_Price               = src.Item_Price,
            Quantity                 = src.Quantity,
            Total_Price              = src.Total_Price,
            NHS_Charge               = src.NHS_Charge,
            Invoice_Amount           = src.Invoice_Amount,
            Invoice_Amount_Outstanding = src.Invoice_Amount_Outstanding,
            Invoice_NHS_Amount       = src.Invoice_NHS_Amount,
            DW_Updated_At            = SYSUTCDATETIME()
        FROM Gold.Fact_Invoice_Items tgt
        INNER JOIN #src src ON tgt.bk_Invoice_Item_ID = src.bk_Invoice_Item_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Account] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Invoice] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Due] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Item_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Reference] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Payment_Terms] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Footnote] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Item_Price] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Quantity] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Price] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Amount] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Amount_Outstanding] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_NHS_Amount] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Account] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Invoice] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Due] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Item_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Reference] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Payment_Terms] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Footnote] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Item_Price] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Quantity] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Price] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Amount] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Amount_Outstanding] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_NHS_Amount] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Invoice_Items (
            Tenant_ID,
            bk_Invoice_Item_ID,
            fk_Patient, fk_Practitioner, fk_Payment_Plan, fk_Treatment_Plan,
            fk_Account, fk_Practice_Site, fk_User,
            fk_Date_Invoice, fk_Date_Due, fk_Date_Paid, fk_Date_Created,
            Invoice_ID, Treatment_Plan_Item_ID, Sundry_ID, Item_Name,
            Invoice_Reference, Invoice_Payment_Terms, Invoice_Footnote, Invoice_Paid,
            Item_Price, Quantity, Total_Price, NHS_Charge,
            Invoice_Amount, Invoice_Amount_Outstanding, Invoice_NHS_Amount,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Invoice_Item_ID,
            src.fk_Patient, src.fk_Practitioner, src.fk_Payment_Plan, src.fk_Treatment_Plan,
            src.fk_Account, src.fk_Practice_Site, src.fk_User,
            src.fk_Date_Invoice, src.fk_Date_Due, src.fk_Date_Paid, src.fk_Date_Created,
            src.Invoice_ID, src.Treatment_Plan_Item_ID, src.Sundry_ID, src.Item_Name,
            src.Invoice_Reference, src.Invoice_Payment_Terms, src.Invoice_Footnote, src.Invoice_Paid,
            src.Item_Price, src.Quantity, src.Total_Price, src.NHS_Charge,
            src.Invoice_Amount, src.Invoice_Amount_Outstanding, src.Invoice_NHS_Amount,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Invoice_Items tgt WHERE tgt.bk_Invoice_Item_ID = src.bk_Invoice_Item_ID AND tgt.Tenant_ID = src.Tenant_ID);
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
