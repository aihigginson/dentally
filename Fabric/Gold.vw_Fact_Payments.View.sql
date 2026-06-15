--------------------------------------------------------------------
--  View   :  Gold.vw_Fact_Payments
--  Author :  AIH
--  Purpose:  Presentation layer over the delta-pure Fact_Payments table. The rare
--            deposit columns are re-attached via a LEFT JOIN to the positive set
--            Gold.Payment_Deposit (absent => not a deposit), rather than being
--            materialised on every fact row. Meta.usp_Create_Gold_Views wraps this
--            view 1-1 into PBI.[_Payments] (vw_<X> supersedes table <X>); the PBI
--            view stays a purely cosmetic rename -- no processing.
--  History:
--    *01     15/06/2026  AIH Initial release (Is_Deposit / Deposit_Amount off the table)
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [Gold].[vw_Fact_Payments]
GO
CREATE VIEW [Gold].[vw_Fact_Payments]
AS
SELECT
    f.pk_Payment,
    f.Tenant_ID,
    f.bk_Payment_ID,
    f.fk_Patient, f.fk_Practitioner, f.fk_Practice_Site, f.fk_Date_Payment,
    f.Payment_Method, f.Payment_Amount,
    -- Deposit is the sparse exception: LEFT JOIN the positive set.
    CAST(CASE WHEN dep.Payment_ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS Is_Deposit,
    CAST(ISNULL(dep.Deposit_Amount, 0) AS DECIMAL(12,2))               AS Deposit_Amount,
    f.DW_Created_At,
    f.DW_Updated_At
FROM Gold.Fact_Payments f
LEFT JOIN Gold.Payment_Deposit dep ON dep.Tenant_ID = f.Tenant_ID AND dep.Payment_ID = f.bk_Payment_ID
GO
