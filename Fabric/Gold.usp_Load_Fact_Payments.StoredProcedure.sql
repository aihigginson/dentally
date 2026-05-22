--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Payments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Payments
--  Author           :  AIH
--  Initial Date     :  22/05/2026
--  History          :
--    *01     22/05/2026  AIH  Initial Release
--  Notes:
--    Grain  : One row per payment (Silver.Payments).
--    Pattern: Incremental DELETE + UPDATE + INSERT keyed on bk_Payment_ID + Tenant_ID.
--    Deposit logic:
--      A payment is a deposit when money has been received but not yet earned.
--      Deposit_Amount = Amount_Unexplained (unallocated)
--                     + allocations to invoice items for incomplete treatment plans.
--      Deleted payments excluded.
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Fact_Payments @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Payments]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Payments]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
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

        -- ── Deposit amounts per payment ──────────────────────────────────────────
        -- Sum of allocations that point to invoice items for incomplete treatment plans.
        SELECT
            pe.Payment_ID,
            pe.Tenant_ID,
            SUM(pa.Amount)                                     AS Incomplete_Plan_Amount
        INTO #dep
        FROM   Silver.Payment_Explanations pe
        JOIN   Silver.Payment_Allocations  pa
               ON  pa.Payment_Explanation_ID = pe.Explanation_ID
               AND pa.Tenant_ID              = pe.Tenant_ID
        JOIN   Silver.Invoice_Items        ii
               ON  ii.Id        = pa.Invoice_Item_ID
               AND ii.Tenant_ID = pe.Tenant_ID
        JOIN   Silver.Treatment_Plans      tp
               ON  tp.Id        = ii.Treatment_Plan_ID
               AND tp.Tenant_ID = pe.Tenant_ID
        WHERE  tp.Completed = 0
        GROUP BY pe.Payment_ID, pe.Tenant_ID;

        -- ── Source ────────────────────────────────────────────────────────────────
        SELECT
            p.Tenant_ID,
            p.Payment_ID                                       AS bk_Payment_ID,
            ISNULL(dpat.pk_Patient,       -1)                  AS fk_Patient,
            ISNULL(dpr.pk_Practitioner,   -1)                  AS fk_Practitioner,
            ISNULL(dps.pk_Practice_Site,  -1)                  AS fk_Practice_Site,
            dd.pk_Date                                         AS fk_Date_Payment,
            NULLIF(TRIM(p.Method), '')                         AS Payment_Method,
            CAST(ISNULL(p.Amount, 0) AS DECIMAL(12,2))         AS Payment_Amount,
            CAST(
                CASE
                    WHEN (ISNULL(p.Amount_Unexplained, 0)
                         + ISNULL(dep.Incomplete_Plan_Amount, 0)) > 0
                    THEN 1 ELSE 0
                END AS BIT)                                    AS Is_Deposit,
            CAST(
                ISNULL(p.Amount_Unexplained, 0)
                + ISNULL(dep.Incomplete_Plan_Amount, 0)
                AS DECIMAL(12,2))                              AS Deposit_Amount
        INTO #src
        FROM Silver.Payments p
        LEFT JOIN Gold.Dim_Patients       dpat ON dpat.Patient_ID      = p.Patient_ID      AND dpat.Tenant_ID = p.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners  dpr  ON dpr.Practitioner_ID  = p.Practitioner_ID AND dpr.Tenant_ID  = p.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites dps  ON dps.Site_ID          = p.Site_ID         AND dps.Tenant_ID  = p.Tenant_ID
        LEFT JOIN Gold.Dim_Date           dd   ON dd.Full_Date          = p.Dated_On
        LEFT JOIN #dep                    dep  ON dep.Payment_ID        = p.Payment_ID      AND dep.Tenant_ID  = p.Tenant_ID
        WHERE (p.Deleted = 0 OR p.Deleted IS NULL)
          AND p.Payment_ID IS NOT NULL;

        -- ── Remove rows no longer in source ──────────────────────────────────────
        DELETE tgt
        FROM Gold.Fact_Payments tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src
            WHERE bk_Payment_ID = tgt.bk_Payment_ID AND Tenant_ID = tgt.Tenant_ID
        );
        SET @My_Deletes = @@ROWCOUNT;

        -- ── Update changed rows ───────────────────────────────────────────────────
        UPDATE tgt SET
            fk_Patient        = src.fk_Patient,
            fk_Practitioner   = src.fk_Practitioner,
            fk_Practice_Site  = src.fk_Practice_Site,
            fk_Date_Payment   = src.fk_Date_Payment,
            Payment_Method    = src.Payment_Method,
            Payment_Amount    = src.Payment_Amount,
            Is_Deposit        = src.Is_Deposit,
            Deposit_Amount    = src.Deposit_Amount,
            DW_Updated_At     = SYSUTCDATETIME()
        FROM Gold.Fact_Payments tgt
        INNER JOIN #src src
               ON  tgt.bk_Payment_ID = src.bk_Payment_ID
               AND tgt.Tenant_ID     = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(tgt.fk_Patient       AS VARCHAR(50)), ''),
            ISNULL(CAST(tgt.fk_Practitioner  AS VARCHAR(50)), ''),
            ISNULL(CAST(tgt.fk_Practice_Site AS VARCHAR(50)), ''),
            ISNULL(CAST(tgt.fk_Date_Payment  AS VARCHAR(50)), ''),
            ISNULL(tgt.Payment_Method, ''),
            ISNULL(CAST(tgt.Payment_Amount   AS VARCHAR(50)), ''),
            ISNULL(CAST(tgt.Is_Deposit       AS VARCHAR(10)), ''),
            ISNULL(CAST(tgt.Deposit_Amount   AS VARCHAR(50)), '')
        )) <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(src.fk_Patient       AS VARCHAR(50)), ''),
            ISNULL(CAST(src.fk_Practitioner  AS VARCHAR(50)), ''),
            ISNULL(CAST(src.fk_Practice_Site AS VARCHAR(50)), ''),
            ISNULL(CAST(src.fk_Date_Payment  AS VARCHAR(50)), ''),
            ISNULL(src.Payment_Method, ''),
            ISNULL(CAST(src.Payment_Amount   AS VARCHAR(50)), ''),
            ISNULL(CAST(src.Is_Deposit       AS VARCHAR(10)), ''),
            ISNULL(CAST(src.Deposit_Amount   AS VARCHAR(50)), '')
        ));
        SET @My_Updates = @@ROWCOUNT;

        -- ── Insert new rows ───────────────────────────────────────────────────────
        INSERT INTO Gold.Fact_Payments (
            Tenant_ID, bk_Payment_ID,
            fk_Patient, fk_Practitioner, fk_Practice_Site, fk_Date_Payment,
            Payment_Method, Payment_Amount, Is_Deposit, Deposit_Amount,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_Payment_ID,
            src.fk_Patient, src.fk_Practitioner, src.fk_Practice_Site, src.fk_Date_Payment,
            src.Payment_Method, src.Payment_Amount, src.Is_Deposit, src.Deposit_Amount,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (
            SELECT 1 FROM Gold.Fact_Payments tgt
            WHERE tgt.bk_Payment_ID = src.bk_Payment_ID AND tgt.Tenant_ID = src.Tenant_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #dep;
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
