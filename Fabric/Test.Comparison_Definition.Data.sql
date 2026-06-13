/****** Seed data: [Test].[Comparison_Definition] ******/
-- Cross-layer reconciliation rules. PASS when value(A) - value(B) = Expected.
-- Almost all expect 0 (full, consistent record sets Bronze -> Silver -> Gold).
-- The sentinel demo expects -1 (Gold dimension carries one extra -1 row).
-- Regression (Current vs Baseline per metric) is implicit and not listed here.
SET NOCOUNT ON
GO
TRUNCATE TABLE [Test].[Comparison_Definition]
GO
INSERT INTO [Test].[Comparison_Definition]
    ([Comparison_Name], [Metric_A], [Metric_B], [Expected_Difference], [Description], [Is_Active])
VALUES
-- -- Patients ----------------------------------------------------------------
 ('CMP_BS_PATIENTS','BRONZE_PATIENTS_T11','SILVER_PATIENTS_T11',0,'Bronze = Silver patient rows',1)
,('CMP_SG_PATIENTS','SILVER_PATIENTS_T11','GOLD_PATIENTS_T11',0,'Silver = Gold patient rows (sentinel excluded)',1)
,('CMP_SENTINEL_PATIENTS','SILVER_PATIENTS_T11','GOLD_PATIENTS_T11_INC_SENTINEL',-1,'Silver one fewer than Gold incl the -1 sentinel; demonstrates a constant offset',1)
-- -- Appointments ------------------------------------------------------------
,('CMP_BS_APPOINTMENTS','BRONZE_APPOINTMENTS_T11','SILVER_APPOINTMENTS_T11',0,'Bronze = Silver appointment rows',1)
,('CMP_SG_APPOINTMENTS','SILVER_APPOINTMENTS_T11','GOLD_APPOINTMENTS_T11',0,'Silver = Gold appointment rows',1)
-- -- Treatment Appointments --------------------------------------------------
,('CMP_BS_TREATMENT_APPOINTMENTS','BRONZE_TREATMENT_APPOINTMENTS_T11','SILVER_TREATMENT_APPOINTMENTS_T11',0,'Bronze = Silver treatment appointment rows',1)
,('CMP_SG_TREATMENT_APPOINTMENTS','SILVER_TREATMENT_APPOINTMENTS_T11','GOLD_TREATMENT_APPOINTMENTS_T11',0,'Silver = Gold treatment appointment rows',1)
-- -- Invoice Items -----------------------------------------------------------
,('CMP_BS_INVOICE_ITEMS','BRONZE_INVOICE_ITEMS_T11','SILVER_INVOICE_ITEMS_T11',0,'Bronze = Silver invoice item rows',1)
,('CMP_SG_INVOICE_ITEMS','SILVER_INVOICE_ITEMS_T11','GOLD_INVOICE_ITEMS_T11',0,'Silver = Gold invoice item rows',1)
-- -- Recalls -----------------------------------------------------------------
,('CMP_BS_RECALLS','BRONZE_RECALLS_T11','SILVER_RECALLS_T11',0,'Bronze = Silver recall rows',1)
,('CMP_SG_RECALLS','SILVER_RECALLS_T11','GOLD_RECALLS_T11',0,'Silver = Gold recall rows',1)
-- -- Practitioners -----------------------------------------------------------
,('CMP_BS_PRACTITIONERS','BRONZE_PRACTITIONERS_T11','SILVER_PRACTITIONERS_T11',0,'Bronze = Silver practitioner rows',1)
,('CMP_SG_PRACTITIONERS','SILVER_PRACTITIONERS_T11','GOLD_PRACTITIONERS_T11',0,'Silver = Gold practitioner rows',1)
-- -- Treatments --------------------------------------------------------------
,('CMP_BS_TREATMENTS','BRONZE_TREATMENTS_T11','SILVER_TREATMENTS_T11',0,'Bronze = Silver treatment rows',1)
,('CMP_SG_TREATMENTS','SILVER_TREATMENTS_T11','GOLD_TREATMENTS_T11',0,'Silver = Gold treatment rows',1)
-- -- Sites -------------------------------------------------------------------
,('CMP_BS_SITES','BRONZE_SITES_T11','SILVER_SITES_T11',0,'Bronze = Silver site rows',1)
,('CMP_SG_SITES','SILVER_SITES_T11','GOLD_SITES_T11',0,'Silver = Gold site rows',1)
-- -- Invoices header + control total -----------------------------------------
,('CMP_BS_INVOICES','BRONZE_INVOICES_T11','SILVER_INVOICES_T11',0,'Bronze = Silver invoice header rows',1)
,('CMP_BS_INVOICED_AMOUNT','BRONZE_INVOICED_AMOUNT_T11','SILVER_INVOICED_AMOUNT_T11',0,'Bronze = Silver total invoiced amount',1)
GO
