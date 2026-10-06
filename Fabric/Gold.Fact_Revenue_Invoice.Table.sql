/****** Object: Table [Gold].[Fact_Revenue_Invoice] ******/
-- One row per PRIVATE invoice line. The first of the four revenue variants; Gold.vw_Fact_Revenue
-- unions them back into the consolidated fact the reports have always read.
--
-- ==> THE VARIANTS WERE NEVER THE SAME SHAPE, THEY JUST SHARED A TABLE. <== Invoice lines carry an
-- invoice, a treatment, an item name, a unit price and a quantity. Capitation carries none of those
-- and a payment plan instead. NHS carries a claim and a UDA count. One table meant every row paid
-- for every other variant's columns in NULLs, and every report that wanted one variant filtered a
-- string out of ~830k mixed rows. Split, a discounts or deposits report reads this table alone.
--
-- ==> NHS_Charge AND Is_Estimated_Plan ARE GONE ON PURPOSE. <== Both were constants here, not
-- missing data: the loader takes only lines WHERE ISNULL(NHS_Charge,0) = 0 -- an NHS patient charge
-- is a slice of the UDA value, valued by Fact_Revenue_NHS, and loading both would count it twice --
-- and nothing on an invoice line is an estimate. The view re-supplies both as literals so the
-- consolidated shape is unchanged.
--
-- (Built by Gold.usp_Load_Fact_Revenue, DROP/CREATE full rebuild.)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Revenue_Invoice]
GO
CREATE TABLE [Gold].[Fact_Revenue_Invoice] (
      [pk_Revenue_Invoice]  BIGINT IDENTITY   NOT NULL,
      [Tenant_ID]           INT               NOT NULL,
      -- Standard_Treatment_Category, or 'Sundries' for a sundry line, or 'Other'. A real column
      -- here: unlike the other three variants, this one genuinely varies row to row.
      [Revenue_Category]    VARCHAR(100)      NOT NULL,
      [fk_Invoice]          BIGINT            NOT NULL,
      [fk_Patient]          BIGINT            NOT NULL,
      [fk_Practitioner]     BIGINT            NOT NULL,
      [fk_Practice_Site]    BIGINT            NOT NULL,
      [fk_Payment_Plan]     BIGINT            NOT NULL,
      [fk_Treatment]        BIGINT            NOT NULL,
      [fk_Date]             BIGINT            NOT NULL,
      [Amount]              DECIMAL(18,6)     NOT NULL,
      [bk_Invoice_Item_ID]  VARCHAR(100)      NULL,
      [Item_Name]           VARCHAR(255)      NULL,
      [Item_Price]          DECIMAL(18,4)     NULL,
      [Quantity]            DECIMAL(18,4)     NULL,
      [DW_Created_At]       DATETIME2(3)      NOT NULL
)
GO
