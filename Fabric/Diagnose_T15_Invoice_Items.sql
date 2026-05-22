-- =============================================================================
-- Diagnose_T15_Invoice_Items.sql
-- Diagnoses and fixes the duplicate rows in Gold.Fact_Invoice_Items for T15.
--
-- Root cause: Silver.Invoices JOIN in usp_Load_Fact_Invoice_Items was missing
-- AND inv.Tenant_ID = ii.Tenant_ID.  When IDs from T15 invoices (15001-15005)
-- collide with same-numbered invoices in another tenant, each T15 item gets
-- two rows in the fact table — one with correct FKs, one with fk_Patient=-1.
-- The UPSERT's DELETE only removes rows absent from Silver, so duplicates with
-- the same bk_Invoice_Item_ID survive every subsequent SP run.
-- =============================================================================

SET NOCOUNT ON;

-- ── Step 1: current state ────────────────────────────────────────────────────

PRINT '=== Gold.Fact_Invoice_Items for T15 ===';
SELECT
    COUNT(*)                        AS Row_Count,        -- expect 8 after fix
    SUM(Total_Price)                AS Total_Price,      -- expect 4500.00
    SUM(CASE WHEN fk_Patient = -1 THEN 1 ELSE 0 END) AS Ghost_Patient_Rows
FROM Gold.Fact_Invoice_Items
WHERE Tenant_ID = 15;

-- ── Step 2: show duplicates ──────────────────────────────────────────────────

PRINT '=== Duplicate bk_Invoice_Item_IDs (should be empty after fix) ===';
SELECT
    bk_Invoice_Item_ID,
    COUNT(*)          AS Copies,
    SUM(Total_Price)  AS Inflated_Total
FROM Gold.Fact_Invoice_Items
WHERE Tenant_ID = 15
GROUP BY bk_Invoice_Item_ID
HAVING COUNT(*) > 1;

-- ── Step 3: confirm the cross-tenant invoice collision ───────────────────────

PRINT '=== Cross-tenant invoice ID collisions (T15 invoice IDs in other tenants) ===';
SELECT
    inv.Id          AS Invoice_ID,
    inv.Tenant_ID   AS Colliding_Tenant,
    inv.Patient_ID,
    inv.Amount
FROM Silver.Invoices inv
WHERE inv.Id IN (SELECT Invoice_ID FROM Silver.Invoice_Items WHERE Tenant_ID = 15)
  AND inv.Tenant_ID <> 15
ORDER BY inv.Id;

-- ── Step 4: verify SP definition has the fix ─────────────────────────────────
-- Should contain: inv.Tenant_ID = ii.Tenant_ID

PRINT '=== SP definition check (should show the Tenant_ID guard line) ===';
SELECT
    CASE
        WHEN OBJECT_DEFINITION(OBJECT_ID('Gold.usp_Load_Fact_Invoice_Items'))
             LIKE '%inv.Tenant_ID = ii.Tenant_ID%'
        THEN 'FIX IS DEPLOYED'
        ELSE 'FIX NOT YET DEPLOYED — redeploy SP first'
    END AS SP_Status;

-- ── Step 5: fix — delete T15 rows and reload ─────────────────────────────────
-- Only run this AFTER Step 4 confirms "FIX IS DEPLOYED".
-- Comment out if you want to inspect results from steps 1-4 first.

/*
PRINT '=== Deleting T15 rows from Gold.Fact_Invoice_Items ===';
DELETE FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 15;
PRINT CONCAT('Deleted: ', @@ROWCOUNT, ' rows');

PRINT '=== Re-running usp_Load_Fact_Invoice_Items ===';
DECLARE @i BIGINT = 0, @u BIGINT = 0, @d BIGINT = 0;
EXEC Gold.usp_Load_Fact_Invoice_Items
    @Mode        = 'PROD',
    @Run_Inserts = @i OUT,
    @Run_Updates = @u OUT,
    @Run_Deletes = @d OUT;
PRINT CONCAT('Inserts: ', @i, '  Updates: ', @u, '  Deletes: ', @d);

PRINT '=== Verify after reload ===';
SELECT
    COUNT(*)       AS Row_Count,
    SUM(Total_Price) AS Total_Price
FROM Gold.Fact_Invoice_Items
WHERE Tenant_ID = 15;
*/
