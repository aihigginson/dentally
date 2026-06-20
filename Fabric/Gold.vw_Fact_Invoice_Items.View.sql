--------------------------------------------------------------------
--  View   :  Gold.vw_Fact_Invoice_Items
--  Author :  AIH
--  Purpose:  Presentation source for the line-grain invoice fact. Since the grain
--            split (20/06/2026) the invoice header amounts/attributes and the derived
--            Aged_Debt_Band / Is_Discount moved to Gold.Fact_Invoices / Gold.Dim_Invoices
--            (+ vw_Dim_Invoices), so this view is now a 1-1 passthrough of the line
--            columns. Kept so Meta.usp_Create_Gold_Views wraps it into PBI.[_Invoice Items]
--            (stable name) and skips the table's own PBI view.
--  History:
--    *01     14/06/2026  AIH Initial release (Aged_Debt_Band moved off the table)
--    *02     20/06/2026  AIH Grain split: dropped folded invoice columns + Aged_Debt_Band
--                            + Is_Discount; added fk_Invoice; now a passthrough.
--    *03     20/06/2026  AIH Added fk_Treatment (line -> treatment-plan-item -> Dim_Treatments).
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
    f.fk_Invoice,
    f.fk_Patient, f.fk_Practitioner, f.fk_Payment_Plan, f.fk_Treatment_Plan, f.fk_Treatment,
    f.fk_Account, f.fk_Practice_Site, f.fk_User,
    f.fk_Date_Invoice, f.fk_Date_Created,
    f.Invoice_ID, f.Treatment_Plan_Item_ID, f.Sundry_ID, f.Item_Name,
    f.Item_Price, f.Quantity, f.Total_Price, f.NHS_Charge,
    f.DW_Created_At,
    f.DW_Updated_At
FROM Gold.Fact_Invoice_Items f
GO
