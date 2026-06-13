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

-- =====================================================================
-- KPI metrics derived from the Tabular Editor DAX measures (Gold layer).
-- These are the DETERMINISTIC base value measures + their ratio
-- numerators/denominators for Tenant 11. Excluded (time-sensitive, per
-- the agreed rule): all Target / vs Target / BG colour measures, every
-- _KPI Snapshot point-in-time measure (Outstanding Invoices, Active /
-- Lapsed Patients, Overdue Recalls, Open Courses Value), the _Current
-- aggregates (Patient Retention, Recalls Overdue Not Sent, Days Until
-- Free) and any TODAY()-based measure (Open Courses Without Appointment,
-- NHS FY YTD). Capture the constituent parts of every ratio, never the
-- ratio itself.
-- =====================================================================
INSERT INTO [Test].[Metric_Definition]
    ([Metric_Name], [Metric_Group], [Layer], [Value_Type], [SQL_Text], [Description], [Is_Active])
VALUES
-- -- Daily aggregate: appointment/clinical components (Scheduling/Clinical/Patients) --
 ('GOLD_AGG_APPOINTMENTS_T11','KPI Component','Gold','count','SELECT SUM(Appointments) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','Appointments (denominator for DNA Rate, BBYL, Cancellation Frequency, Exam Ratio)',1)
,('GOLD_AGG_DNA_APPOINTMENTS_T11','KPI Component','Gold','count','SELECT SUM(DNA_Appointments) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','DNA appointments (numerator for DNA Rate)',1)
,('GOLD_AGG_BBYL_APPOINTMENTS_T11','KPI Component','Gold','count','SELECT SUM(BBYL_Appointments) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','Book-before-you-leave appointments (numerator for BBYL)',1)
,('GOLD_AGG_CANCELLED_APPOINTMENTS_T11','KPI Component','Gold','count','SELECT SUM(Cancelled_Appointments) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','Cancelled appointments (numerator for Cancellation Frequency; denominator for Short Notice Rate)',1)
,('GOLD_AGG_SHORT_NOTICE_CANCELLATIONS_T11','KPI Component','Gold','count','SELECT SUM(Short_Notice_Cancellations) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','Short-notice cancellations (numerator for Short Notice Cancellation Rate)',1)
,('GOLD_AGG_EXAM_COUNT_T11','KPI Component','Gold','count','SELECT SUM(Exam_Count) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','Exam appointments (numerator for Exam Ratio)',1)
,('GOLD_AGG_NEW_PATIENTS_T11','KPI Value','Gold','count','SELECT COUNT(DISTINCT fk_Patient) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11 AND New_Patient = 1','New Patients (distinct patients flagged new)',1)
,('GOLD_AGG_APPOINTMENT_HOURS_T11','KPI Component','Gold','number','SELECT SUM(Appointment_Hours) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','Appointment hours (numerator for Chair Utilisation)',1)
,('GOLD_AGG_WORKED_HOURS_DEDUP_T11','KPI Component','Gold','number','SELECT SUM(wh) FROM (SELECT fk_Practitioner, fk_Date, MAX(Worked_Hours) AS wh FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11 GROUP BY fk_Practitioner, fk_Date) x','Worked hours deduplicated per practitioner-day (denominator for Chair Utilisation)',1)
,('GOLD_AGG_NHS_UDAS_T11','KPI Value','Gold','number','SELECT SUM(NHS_UDAs) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','NHS UDAs delivered',1)
,('GOLD_AGG_NHS_UOAS_T11','KPI Value','Gold','number','SELECT SUM(NHS_UOAs) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','NHS UOAs delivered',1)
,('GOLD_AGG_NHS_REVENUE_T11','KPI Value','Gold','currency','SELECT SUM(NHS_Revenue) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','NHS revenue from the daily aggregate',1)
,('GOLD_AGG_PRIVATE_REVENUE_T11','KPI Value','Gold','currency','SELECT SUM(Private_Revenue) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11','Private revenue from the daily aggregate',1)
-- -- Invoice items: revenue (Revenue page) --
,('GOLD_TOTAL_REVENUE_T11','KPI Value','Gold','currency','SELECT SUM(Total_Price) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11','Total Revenue (sum of invoice item Total Price)',1)
,('GOLD_NHS_REVENUE_INV_T11','KPI Value','Gold','currency','SELECT SUM(Total_Price) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND NHS_Charge > 0','NHS Revenue (invoice items with NHS Charge > 0)',1)
,('GOLD_PRIVATE_REVENUE_INV_T11','KPI Value','Gold','currency','SELECT SUM(Total_Price) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND NHS_Charge = 0','Private Revenue (invoice items with NHS Charge = 0)',1)
,('GOLD_REVENUE_NHS_OR_PRIVATE_INV_T11','KPI Component','Gold','currency','SELECT SUM(Total_Price) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND NHS_Charge IS NOT NULL','NHS + Private revenue combined (NHS Charge not null) for the revenue-split reconcile',1)
-- -- Treatment plans: acceptance / open courses / plan value / UDA (Clinical/NHS) --
,('GOLD_TP_TOTAL_T11','KPI Component','Gold','count','SELECT SUM(Treatment_Plan_Count) FROM Gold.Dim_Treatment_Plans WHERE Tenant_ID = 11','All treatment plans (denominator for Treatment Acceptance Rate)',1)
,('GOLD_TP_STARTED_T11','KPI Component','Gold','count','SELECT SUM(Treatment_Plan_Count) FROM Gold.Dim_Treatment_Plans WHERE Tenant_ID = 11 AND Start_Date IS NOT NULL','Started treatment plans (numerator for Acceptance Rate; denominator for Average Plan Value)',1)
,('GOLD_TP_OPEN_COURSES_T11','KPI Value','Gold','count','SELECT SUM(Treatment_Plan_Count) FROM Gold.Dim_Treatment_Plans WHERE Tenant_ID = 11 AND Completed = 0 AND Start_Date IS NOT NULL','Open Courses (started, not completed)',1)
,('GOLD_TP_PRIVATE_VALUE_T11','KPI Component','Gold','currency','SELECT SUM(Private_Treatment_Value) FROM Gold.Dim_Treatment_Plans WHERE Tenant_ID = 11','Private treatment value (numerator for Average Plan Value)',1)
,('GOLD_TP_NHS_UDA_VALUE_T11','KPI Component','Gold','number','SELECT SUM(NHS_UDA_Value) FROM Gold.Dim_Treatment_Plans WHERE Tenant_ID = 11','NHS UDA Contracted (denominator for NHS UDA Completion Rate)',1)
,('GOLD_TP_NHS_COMPLETED_UDA_VALUE_T11','KPI Component','Gold','number','SELECT SUM(NHS_Completed_UDA_Value) FROM Gold.Dim_Treatment_Plans WHERE Tenant_ID = 11','NHS UDA Completed (numerator for NHS UDA Completion Rate)',1)
GO
