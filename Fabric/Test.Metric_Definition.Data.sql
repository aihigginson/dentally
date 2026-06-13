/****** Seed data: [Test].[Metric_Definition] ******/
-- Starter regression metric set for the deterministic test tenant (Tenant 11).
-- Each SQL_Text returns ONE scalar. Add/disable rows here over time to grow
-- interface coverage. All hardcoded to Tenant_ID = 11 (the reproducible tenant).
SET NOCOUNT ON
GO
TRUNCATE TABLE [Test].[Metric_Definition]
GO
INSERT INTO [Test].[Metric_Definition]
    ([Metric_Name], [Metric_Group], [Layer], [Value_Type], [SQL_Text], [Description], [Is_Active])
VALUES
-- -- Patients (dimension) ----------------------------------------------------
 ('BRONZE_PATIENTS_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Patients WHERE Tenant_ID = 11','Patient rows in Bronze for tenant 11',1)
,('SILVER_PATIENTS_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Patients WHERE Tenant_ID = 11','Patient rows in Silver for tenant 11',1)
,('GOLD_PATIENTS_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Dim_Patients WHERE Tenant_ID = 11','Patient rows in Gold (excl sentinel) for tenant 11',1)
,('GOLD_PATIENTS_T11_INC_SENTINEL','Sentinel Demo','Gold','count','SELECT COUNT(*) FROM Gold.Dim_Patients WHERE Tenant_ID = 11 OR Tenant_ID = -1','Patient rows in Gold INCLUDING the -1 sentinel; demonstrates a non-zero expected offset',1)
-- -- Appointments (fact) -----------------------------------------------------
,('BRONZE_APPOINTMENTS_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Appointments WHERE Tenant_ID = 11','Appointment rows in Bronze for tenant 11',1)
,('SILVER_APPOINTMENTS_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Appointments WHERE Tenant_ID = 11','Appointment rows in Silver for tenant 11',1)
,('GOLD_APPOINTMENTS_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11','Appointment rows in Gold for tenant 11',1)
-- -- Treatment Appointments (fact) -------------------------------------------
,('BRONZE_TREATMENT_APPOINTMENTS_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Treatment_Appointments WHERE Tenant_ID = 11','Treatment appointment rows in Bronze for tenant 11',1)
,('SILVER_TREATMENT_APPOINTMENTS_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Treatment_Appointments WHERE Tenant_ID = 11','Treatment appointment rows in Silver for tenant 11',1)
,('GOLD_TREATMENT_APPOINTMENTS_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Appointments WHERE Tenant_ID = 11','Treatment appointment rows in Gold for tenant 11',1)
-- -- Invoice Items (fact) ----------------------------------------------------
,('BRONZE_INVOICE_ITEMS_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Invoice_Items WHERE Tenant_ID = 11','Invoice item rows in Bronze for tenant 11',1)
,('SILVER_INVOICE_ITEMS_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Invoice_Items WHERE Tenant_ID = 11','Invoice item rows in Silver for tenant 11',1)
,('GOLD_INVOICE_ITEMS_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11','Invoice item rows in Gold for tenant 11',1)
-- -- Recalls (fact) ----------------------------------------------------------
,('BRONZE_RECALLS_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Recalls WHERE Tenant_ID = 11','Recall rows in Bronze for tenant 11',1)
,('SILVER_RECALLS_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Recalls WHERE Tenant_ID = 11','Recall rows in Silver for tenant 11',1)
,('GOLD_RECALLS_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11','Recall rows in Gold for tenant 11',1)
-- -- Practitioners (dimension) -----------------------------------------------
,('BRONZE_PRACTITIONERS_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Practitioners WHERE Tenant_ID = 11','Practitioner rows in Bronze for tenant 11',1)
,('SILVER_PRACTITIONERS_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Practitioners WHERE Tenant_ID = 11','Practitioner rows in Silver for tenant 11',1)
,('GOLD_PRACTITIONERS_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Dim_Practitioners WHERE Tenant_ID = 11','Practitioner rows in Gold (excl sentinel) for tenant 11',1)
-- -- Treatments (dimension) --------------------------------------------------
,('BRONZE_TREATMENTS_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Treatments WHERE Tenant_ID = 11','Treatment rows in Bronze for tenant 11',1)
,('SILVER_TREATMENTS_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Treatments WHERE Tenant_ID = 11','Treatment rows in Silver for tenant 11',1)
,('GOLD_TREATMENTS_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Dim_Treatments WHERE Tenant_ID = 11','Treatment rows in Gold (excl sentinel) for tenant 11',1)
-- -- Sites (dimension) -------------------------------------------------------
,('BRONZE_SITES_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Sites WHERE Tenant_ID = 11','Site rows in Bronze for tenant 11',1)
,('SILVER_SITES_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Sites WHERE Tenant_ID = 11','Site rows in Silver for tenant 11',1)
,('GOLD_SITES_T11','Row Count','Gold','count','SELECT COUNT(*) FROM Gold.Dim_Practice_Sites WHERE Tenant_ID = 11','Site rows in Gold (excl sentinel) for tenant 11',1)
-- -- Invoices (header; no Gold header table, so Bronze/Silver only) -----------
,('BRONZE_INVOICES_T11','Row Count','Bronze','count','SELECT COUNT(*) FROM Bronze.Invoices WHERE Tenant_ID = 11','Invoice header rows in Bronze for tenant 11',1)
,('SILVER_INVOICES_T11','Row Count','Silver','count','SELECT COUNT(*) FROM Silver.Invoices WHERE Tenant_ID = 11','Invoice header rows in Silver for tenant 11',1)
-- -- Control totals (currency) -----------------------------------------------
,('BRONZE_INVOICED_AMOUNT_T11','Control Total','Bronze','currency','SELECT SUM(Amount) FROM Bronze.Invoices WHERE Tenant_ID = 11','Total invoiced amount in Bronze for tenant 11',1)
,('SILVER_INVOICED_AMOUNT_T11','Control Total','Silver','currency','SELECT SUM(Amount) FROM Silver.Invoices WHERE Tenant_ID = 11','Total invoiced amount in Silver for tenant 11',1)
GO
