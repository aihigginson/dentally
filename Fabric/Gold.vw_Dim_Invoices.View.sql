--------------------------------------------------------------------
--  View   :  Gold.vw_Dim_Invoices
--  Author :  AIH
--  Purpose:  Presentation/computed layer over Gold.Dim_Invoices. Adds the two
--            derived invoice-header attributes that must not be materialised on the
--            table:
--              * Aged_Debt_Band -- TIME-derived (days overdue vs "today"); computed
--                LIVE so it is never stale. Unpaid invoices only.
--              * Is_Discount    -- sparse exception (invoice Amount > sum of its line
--                Total Price); LEFT JOIN the tiny positive set Gold.Invoice_Discount.
--            Meta.usp_Create_Gold_Views wraps this 1-1 into PBI.[List Invoices] and
--            skips the table's own PBI view.
--  History:
--    *01     20/06/2026  AIH Initial release (invoice fact split: header attrs +
--                            derived Aged_Debt_Band/Is_Discount moved off the line fact)
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [Gold].[vw_Dim_Invoices]
GO
CREATE VIEW [Gold].[vw_Dim_Invoices]
AS
SELECT
    d.pk_Invoice,
    d.Tenant_ID,
    d.bk_Invoice_ID,
    d.Invoice_Reference,
    d.Payment_Terms,
    d.Footnote,
    d.Invoice_Paid,
    d.Status,
    d.Invoice_Dated_On,
    -- Is_Discount: sparse positive set, LEFT JOINed rather than a mostly-0 flag.
    CAST(CASE WHEN disc.Invoice_ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS Is_Discount,
    -- Time-derived aged-debt banding vs today; unpaid invoices only.
    CASE
        WHEN ISNULL(d.Invoice_Paid, 0) = 1 THEN NULL
        WHEN d.Invoice_Dated_On IS NULL THEN NULL
        WHEN DATEDIFF(DAY, d.Invoice_Dated_On, CAST(SYSUTCDATETIME() AS DATE)) <=  30 THEN '0-30 Days'
        WHEN DATEDIFF(DAY, d.Invoice_Dated_On, CAST(SYSUTCDATETIME() AS DATE)) <=  60 THEN '31-60 Days'
        WHEN DATEDIFF(DAY, d.Invoice_Dated_On, CAST(SYSUTCDATETIME() AS DATE)) <=  90 THEN '61-90 Days'
        WHEN DATEDIFF(DAY, d.Invoice_Dated_On, CAST(SYSUTCDATETIME() AS DATE)) <= 120 THEN '91-120 Days'
        ELSE '120+ Days'
    END AS Aged_Debt_Band,
    d.DW_Created_At,
    d.DW_Updated_At
FROM Gold.Dim_Invoices d
LEFT JOIN Gold.Invoice_Discount disc ON disc.Tenant_ID = d.Tenant_ID AND disc.Invoice_ID = d.bk_Invoice_ID
GO
