/****** Object: Table [Gold].[Fact_Revenue] ******/
-- Unified revenue-line fact: one row per invoice line OR per capitation member-day.
-- Revenue is defined ONCE here, so header/line/category views can't diverge.
-- Revenue_Type = 'Invoice' | 'Capitation'; Revenue_Category = Standard Treatment Category /
-- 'Sundries' / 'Other' / 'Plan Capitation'. fk_Invoice = -1 for capitation and transient orphans.
-- (Built/repopulated by Gold.usp_Load_Fact_Revenue, DROP/CREATE full rebuild.)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Revenue]
GO
CREATE TABLE [Gold].[Fact_Revenue] (
      [pk_Revenue]          BIGINT IDENTITY   NOT NULL,
      [Tenant_ID]           INT               NOT NULL,
      [Revenue_Type]        VARCHAR(20)       NOT NULL,
      [Revenue_Category]    VARCHAR(100)      NOT NULL,
      [fk_Invoice]          BIGINT            NOT NULL,
      [fk_Patient]          BIGINT            NOT NULL,
      [fk_Practitioner]     BIGINT            NOT NULL,
      [fk_Practice_Site]    BIGINT            NOT NULL,
      [fk_Payment_Plan]     BIGINT            NOT NULL,
      [fk_Treatment]        BIGINT            NOT NULL,
      [fk_Date]             BIGINT            NOT NULL,
      [Amount]              DECIMAL(18,6)     NOT NULL,
      [NHS_Charge]          DECIMAL(12,2)     NULL,
      [Is_Estimated_Plan]   BIT               NOT NULL,
      [bk_Invoice_Item_ID]  VARCHAR(100)      NULL,
      [Item_Name]           VARCHAR(255)      NULL,
      [Item_Price]          DECIMAL(18,4)     NULL,
      [Quantity]            DECIMAL(18,4)     NULL,
      [DW_Created_At]       DATETIME2(3)      NOT NULL
)
GO
