--------------------------------------------------------------------
--  View   :  Gold.vw_Fact_Invoice_Items
--  Author :  AIH
--  Purpose:  Presentation/computed layer over the Fact_Invoice_Items table.
--            TIME-DERIVED columns are computed LIVE here so they are never stale
--            under incremental (delta) loads -- the underlying table holds only
--            source-derived data, giving a 1-1 correspondence between a delta load
--            and a full refresh. Aged_Debt_Band (days-overdue banding vs "today")
--            is the time-derived column.
--
--            Convention: a Gold view named vw_<Table> is the presentation source
--            for <Table>. Meta.usp_Create_Gold_Views wraps it 1-1 into the PBI
--            layer (PBI.[_Invoice Items]) and SKIPS the table's own PBI view, so
--            the PBI view stays a purely cosmetic rename -- no processing.
--  History:
--    *01     14/06/2026  AIH Initial release (Aged_Debt_Band moved off the table)
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [Gold].[vw_Fact_Invoice_Items]
GO
CREATE VIEW [Gold].[vw_Fact_Invoice_Items]
AS
SELECT
    f.pk_Invoice_Item,
    f.Tenant_ID,
    f.bk_Invoice_Item_ID,
    f.fk_Patient, f.fk_Practitioner, f.fk_Payment_Plan, f.fk_Treatment_Plan,
    f.fk_Account, f.fk_Practice_Site, f.fk_User,
    f.fk_Date_Invoice, f.fk_Date_Due, f.fk_Date_Paid, f.fk_Date_Created,
    f.Invoice_ID, f.Treatment_Plan_Item_ID, f.Sundry_ID, f.Item_Name,
    f.Invoice_Reference, f.Invoice_Payment_Terms, f.Invoice_Footnote, f.Invoice_Paid,
    f.Item_Price, f.Quantity, f.Total_Price, f.NHS_Charge,
    f.Invoice_Amount, f.Invoice_Amount_Outstanding, f.Invoice_NHS_Amount,
    f.Is_Invoice_Outstanding, f.Is_Discount,
    -- Time-derived: recomputed at query time against the invoice date, so it is
    -- always current and behaves correctly under deltas (mirrors the original load
    -- logic but live). Unpaid only; paid invoices have no aged debt.
    CASE
        WHEN ISNULL(f.Invoice_Paid, 0) = 1 THEN NULL
        WHEN DATEDIFF(DAY, d.Full_Date, CAST(SYSUTCDATETIME() AS DATE)) <=  30 THEN '0-30 Days'
        WHEN DATEDIFF(DAY, d.Full_Date, CAST(SYSUTCDATETIME() AS DATE)) <=  60 THEN '31-60 Days'
        WHEN DATEDIFF(DAY, d.Full_Date, CAST(SYSUTCDATETIME() AS DATE)) <=  90 THEN '61-90 Days'
        WHEN DATEDIFF(DAY, d.Full_Date, CAST(SYSUTCDATETIME() AS DATE)) <= 120 THEN '91-120 Days'
        ELSE '120+ Days'
    END AS Aged_Debt_Band,
    f.DW_Created_At,
    f.DW_Updated_At
FROM Gold.Fact_Invoice_Items f
LEFT JOIN Gold.Dim_Date d ON d.pk_Date = f.fk_Date_Invoice
GO
