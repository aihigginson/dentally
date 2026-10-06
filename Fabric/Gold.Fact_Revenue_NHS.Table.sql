/****** Object: Table [Gold].[Fact_Revenue_NHS] ******/
-- One row per NHS claim, valued at the contract rate. Gold.vw_Fact_Revenue unions this with the
-- other three variants into the consolidated fact.
--
-- ==> NHS INCOME IS THE UDA VALUE, NOT WHAT THE PATIENT PAID AT THE DESK. <== What the practice
-- earns for a course is the band's UDAs at the contract rate, however that sum splits between the
-- patient and the NHS. The split is cash flow between those two and says nothing about what was
-- earned. This is why Fact_Revenue_Invoice excludes any line with an NHS charge on it: the slice
-- the patient paid is already inside the figure below, and loading both would bank it twice.
--
-- The columns the old shared table spelled bk_Invoice_Item_ID / Item_Price / Quantity are named for
-- what they actually hold here. They were never invoice-item columns on these rows -- an NHS claim
-- has no invoice item -- they were simply the nearest-shaped column going spare.
--
-- (Built by Gold.usp_Load_Fact_Revenue, DROP/CREATE full rebuild.)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Revenue_NHS]
GO
CREATE TABLE [Gold].[Fact_Revenue_NHS] (
      [pk_Revenue_NHS]      BIGINT IDENTITY   NOT NULL,
      [Tenant_ID]           INT               NOT NULL,
      -- 'NHS Contract (UDA)' or 'NHS Orthodontic (UOA)' -- ortho is measured in UOAs at a different
      -- contract rate, so the two cannot share a category even though they share a table.
      [Revenue_Category]    VARCHAR(100)      NOT NULL,
      [fk_Patient]          BIGINT            NOT NULL,
      [fk_Practitioner]     BIGINT            NOT NULL,
      [fk_Practice_Site]    BIGINT            NOT NULL,
      [fk_Date]             BIGINT            NOT NULL,
      [Amount]              DECIMAL(18,6)     NOT NULL,
      [bk_NHS_Claim_ID]     VARCHAR(100)      NULL,   -- was bk_Invoice_Item_ID, prefixed 'NHSCLAIM:'
      [Claim_Description]   VARCHAR(255)      NULL,   -- was Item_Name  ('NHS UDA claim band 2')
      [Unit_Value]          DECIMAL(18,4)     NULL,   -- was Item_Price (the UDA or UOA rate)
      [Units]               DECIMAL(18,4)     NULL,   -- was Quantity   (awarded UDA, else expected)
      [DW_Created_At]       DATETIME2(3)      NOT NULL
)
GO
