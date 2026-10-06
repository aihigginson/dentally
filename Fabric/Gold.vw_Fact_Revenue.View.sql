/****** Object: View [Gold].[vw_Fact_Revenue] ******/
-- The consolidated revenue fact, composed from the four variant tables.
--
-- ==> THIS VIEW EXISTS SO THAT NOTHING DOWNSTREAM HAD TO CHANGE. <== It emits the exact column set
-- Gold.Fact_Revenue had as a physical table, in the same types, so its four readers --
-- usp_Load_Aggregate_Practitioner_Contribution, usp_Load_Aggregate_Site_Patient_Current,
-- usp_Load_Aggregate_Site_Patient_Practitioner_Daily and usp_Load_Fact_Metric_Actuals -- carry on
-- reading Gold.Fact_Revenue unchanged, and so does the model: Meta.usp_Create_Gold_Views treats a
-- Gold view named vw_<X> as the source for entity <X>, so this still becomes PBI.[_Revenue].
--
-- The four variant tables ALSO get their own PBI views, which is the point of the split: a
-- capitation report reads capitation, an NHS report reads NHS, and a discounts or deposits report
-- reads invoice lines, instead of every one of them filtering a category string out of ~830k mixed
-- rows. Each needs its own RLS rule in the model -- a new table has none by default.
--
-- ==> Revenue_Type AND THE CONSTANT CATEGORIES ARE LITERALS HERE, NOT STORED. <== Three of the four
-- variants have a single category for every row; storing 600k copies of
-- 'Plan Capitation (estimated)' bought nothing and let the string drift between the loader and the
-- readers. The branch supplies it, so it can only be spelled one way.
--
-- ==> NHS_Charge IS ZERO ON EVERY BRANCH, AND THAT IS NOT A LOSS. <== It was zero on every row of
-- the old table too: invoice lines are filtered to ISNULL(NHS_Charge,0) = 0 because an NHS patient
-- charge is a slice of the UDA value and is banked by the NHS branch instead, and the other three
-- wrote a literal 0. usp_Load_Fact_Metric_Actuals tests it to separate private from NHS revenue, so
-- it is kept, as the same constant it always was.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [Gold].[vw_Fact_Revenue]
GO
CREATE VIEW [Gold].[vw_Fact_Revenue]
AS
-- pk_Revenue: each variant has its own IDENTITY, so a constant offset per branch keeps the key
-- unique across the union. Nothing in the warehouse or the model joins on it -- it is kept only
-- because the model already imports the column, and dropping a column breaks a refresh.
SELECT  i.pk_Revenue_Invoice + 1000000000000 AS pk_Revenue,
        i.Tenant_ID,
        'Invoice'                            AS Revenue_Type,
        i.Revenue_Category,
        i.fk_Invoice,
        i.fk_Patient,
        i.fk_Practitioner,
        i.fk_Practice_Site,
        i.fk_Payment_Plan,
        i.fk_Treatment,
        i.fk_Date,
        i.Amount,
        CAST(0 AS DECIMAL(12,2))             AS NHS_Charge,
        CAST(0 AS BIT)                       AS Is_Estimated_Plan,
        i.bk_Invoice_Item_ID,
        i.Item_Name,
        i.Item_Price,
        i.Quantity,
        i.DW_Created_At
FROM    [Gold].[Fact_Revenue_Invoice] i

UNION ALL

SELECT  n.pk_Revenue_NHS + 2000000000000,
        n.Tenant_ID,
        'NHS',
        n.Revenue_Category,
        CAST(-1 AS BIGINT),                  -- no invoice behind a claim
        n.fk_Patient,
        n.fk_Practitioner,
        n.fk_Practice_Site,
        CAST(-1 AS BIGINT),                  -- no payment plan
        CAST(-1 AS BIGINT),                  -- no treatment
        n.fk_Date,
        n.Amount,
        CAST(0 AS DECIMAL(12,2)),
        CAST(0 AS BIT),
        n.bk_NHS_Claim_ID,
        n.Claim_Description,
        n.Unit_Value,
        n.Units,
        n.DW_Created_At
FROM    [Gold].[Fact_Revenue_NHS] n

UNION ALL

SELECT  c.pk_Revenue_Capitation + 3000000000000,
        c.Tenant_ID,
        'Capitation',
        'Plan Capitation (estimated)',       -- the category says "estimated" because it is
        CAST(-1 AS BIGINT),
        c.fk_Patient,
        c.fk_Practitioner,
        c.fk_Practice_Site,
        c.fk_Payment_Plan,
        CAST(-1 AS BIGINT),
        c.fk_Date,
        c.Amount,
        CAST(0 AS DECIMAL(12,2)),
        c.Is_Estimated_Plan,
        CAST(NULL AS VARCHAR(100)),
        CAST(NULL AS VARCHAR(255)),
        CAST(NULL AS DECIMAL(18,4)),
        CAST(NULL AS DECIMAL(18,4)),
        c.DW_Created_At
FROM    [Gold].[Fact_Revenue_Capitation] c

UNION ALL

-- Both legs, signed, so the consolidated fact still nets to zero across the practice and a
-- practitioner-level figure still moves. fk_Practitioner is this leg's own practitioner, which is
-- what makes a report filtered to one person find their side of it.
SELECT  x.pk_Revenue_Cross_Charge + 4000000000000,
        x.Tenant_ID,
        'Capitation',
        'Plan hygienist cross-charge',
        CAST(-1 AS BIGINT),
        x.fk_Patient,
        x.fk_Practitioner,
        x.fk_Practice_Site,
        x.fk_Payment_Plan,
        CAST(-1 AS BIGINT),
        x.fk_Date,
        x.Amount,
        CAST(0 AS DECIMAL(12,2)),
        x.Is_Estimated_Plan,
        CAST(NULL AS VARCHAR(100)),
        CAST(NULL AS VARCHAR(255)),
        CAST(NULL AS DECIMAL(18,4)),
        CAST(NULL AS DECIMAL(18,4)),
        x.DW_Created_At
FROM    [Gold].[Fact_Revenue_Cross_Charge] x
GO
