-- V150: retire Gold.Fact_Invoice_Items + Gold.Fact_Plan_Capitation (subsumed by Gold.Fact_Revenue).
-- Every warehouse consumer was repointed to Fact_Revenue in this release:
--   * Gold.usp_Load_Fact_Metric_Actuals            (invoice metrics -> Revenue_Type='Invoice';
--                                                    plan_capitation_revenue -> Revenue_Type='Capitation')
--   * Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily (Revenue_Type='Invoice')
--   * Gold.usp_Load_Fact_KPI_Snapshot              (#charged re-sourced from Silver.Invoice_Items;
--                                                    outstanding practitioner from Fact_Invoices.fk_Practitioner)
--   * Gold.usp_Load_Aggregate_Practitioner_Contribution already read Fact_Revenue.
-- The PBI model was cut over to _Revenue and no longer reads the _Invoice Items / _Plan Capitation views.
-- Drop order: PBI views (depend on the tables) -> load SPs -> base tables. Idempotent (IF EXISTS).
DROP VIEW IF EXISTS [PBI].[_Invoice Items];
GO
DROP VIEW IF EXISTS [PBI].[_Plan Capitation];
GO
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Invoice_Items];
GO
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Plan_Capitation];
GO
DROP TABLE IF EXISTS [Gold].[Fact_Invoice_Items];
GO
DROP TABLE IF EXISTS [Gold].[Fact_Plan_Capitation];
GO
