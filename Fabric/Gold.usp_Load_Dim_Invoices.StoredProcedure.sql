--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Invoices] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Invoices
--  Author           :  AIH
--  Initital Date    :  20/06/2026
--  History          :
--    *01     20/06/2026  AIH Initial release. Invoice header dimension (1/invoice).
--                            Upsert pattern (DELETE-orphan + hash UPDATE + ROW_NUMBER
--                            INSERT + -1 seed), mirroring Gold.usp_Load_Dim_Patients.
--                            Also rebuilds Gold.Invoice_Discount from Silver (invoice
--                            Amount > sum of its line Total Price) so Is_Discount is
--                            decoupled from fact load order.
--  To Run			 :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Dim_Invoices @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Invoices]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Invoices]
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
            inv.Tenant_ID                          AS Tenant_ID,
            CAST(inv.Id AS INT)                    AS bk_Invoice_ID,
            NULLIF(TRIM(inv.Reference), '')        AS Invoice_Reference,
            NULLIF(TRIM(inv.Payment_Terms), '')    AS Payment_Terms,
            LEFT(NULLIF(TRIM(inv.Footnote), ''), 255) AS Footnote,
            CAST(ISNULL(inv.Paid, 0) AS BIT)       AS Invoice_Paid,
            NULLIF(TRIM(inv.Status), '')           AS Status,
            CAST(inv.Dated_On AS DATE)             AS Invoice_Dated_On
        INTO #src
        FROM Silver.Invoices inv
        WHERE inv.Id IS NOT NULL;

        -- Remove rows no longer in source (protect the -1 seed)
        DELETE tgt
        FROM Gold.Dim_Invoices tgt
        WHERE NOT EXISTS (SELECT 1 FROM Silver.Invoices s
                          WHERE CAST(s.Id AS INT) = tgt.bk_Invoice_ID AND s.Tenant_ID = tgt.Tenant_ID)
          AND tgt.pk_Invoice <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Invoice_Reference = src.Invoice_Reference,
            Payment_Terms     = src.Payment_Terms,
            Footnote          = src.Footnote,
            Invoice_Paid      = src.Invoice_Paid,
            Status            = src.Status,
            Invoice_Dated_On  = src.Invoice_Dated_On,
            DW_Updated_At     = SYSUTCDATETIME()
        FROM Gold.Dim_Invoices tgt
        INNER JOIN #src src ON tgt.bk_Invoice_ID = src.bk_Invoice_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Invoice_Reference] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Payment_Terms]     AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Footnote]          AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Paid]      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Status]            AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Invoice_Dated_On]  AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Invoice_Reference] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Payment_Terms]     AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Footnote]          AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Paid]      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Status]            AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Invoice_Dated_On]  AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_base BIGINT = ISNULL((SELECT MAX(pk_Invoice) FROM Gold.Dim_Invoices WHERE pk_Invoice > 0), 0);
        INSERT INTO Gold.Dim_Invoices (
            pk_Invoice, Tenant_ID, bk_Invoice_ID, Invoice_Reference, Payment_Terms,
            Footnote, Invoice_Paid, Status, Invoice_Dated_On, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.bk_Invoice_ID),
            src.Tenant_ID, src.bk_Invoice_ID, src.Invoice_Reference, src.Payment_Terms,
            src.Footnote, src.Invoice_Paid, src.Status, src.Invoice_Dated_On, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Invoices tgt
                          WHERE tgt.bk_Invoice_ID = src.bk_Invoice_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (fk_Invoice = -1 for unresolved invoices)
        INSERT INTO Gold.Dim_Invoices (pk_Invoice, Tenant_ID, bk_Invoice_ID, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Invoices WHERE pk_Invoice = -1);

        -- Rebuild the discount "positive" set: invoices whose header Amount exceeds
        -- the sum of their line Total Price. Sourced from Silver so it does not depend
        -- on Fact load order. The invoice dim view LEFT JOINs it for Is_Discount.
        DELETE FROM Gold.Invoice_Discount;
        INSERT INTO Gold.Invoice_Discount (Tenant_ID, Invoice_ID)
        SELECT inv.Tenant_ID, CAST(inv.Id AS INT)
        FROM   Silver.Invoices inv
        JOIN   Silver.Invoice_Items ii ON ii.Invoice_ID = inv.Id AND ii.Tenant_ID = inv.Tenant_ID
        GROUP BY inv.Tenant_ID, CAST(inv.Id AS INT)
        HAVING MAX(ISNULL(inv.Amount, 0)) > SUM(ISNULL(ii.Total_Price, 0));

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
