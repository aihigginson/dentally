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

-- =====================================================================
-- FK integrity: NULL counts on every Gold foreign-key column (tenant 11).
-- Generated by _gen_fk_tests.py. Core entity FKs (Patient/Practitioner/
-- Practice_Site/Site) are asserted = 0 via reconcile rules; other entity
-- FKs and all date FKs are metric-only so the baseline captures the
-- accepted (possibly non-zero) NULL count for optional columns.
-- =====================================================================
INSERT INTO [Test].[Metric_Definition]
    ([Metric_Name], [Metric_Group], [Layer], [Value_Type], [SQL_Text], [Description], [Is_Active])
VALUES
 ('GOLD_ZERO','Constant','Gold','count','SELECT 0','Constant zero, used as Metric_B for = 0 reconcile assertions',1)
,('GOLD_FKNULL_APPT_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_PAYMENT_PLAN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Payment_Plan IS NULL','NULL count of fk_Payment_Plan in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_PRACTICE_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Practice_Site IS NULL','NULL count of fk_Practice_Site in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_USER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_User IS NULL','NULL count of fk_User in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_CANCELLATION_REASON_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Cancellation_Reason IS NULL','NULL count of fk_Cancellation_Reason in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_DATE_START_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Date_Start IS NULL','NULL count of fk_Date_Start in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_DATE_PENDING_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Date_Pending IS NULL','NULL count of fk_Date_Pending in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_APPT_DATE_CREATED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID = 11 AND fk_Date_Created IS NULL','NULL count of fk_Date_Created in Gold.Fact_Appointments (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_PAYMENT_PLAN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Payment_Plan IS NULL','NULL count of fk_Payment_Plan in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_TREATMENT_PLAN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Treatment_Plan IS NULL','NULL count of fk_Treatment_Plan in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_ACCOUNT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Account IS NULL','NULL count of fk_Account in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_PRACTICE_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Practice_Site IS NULL','NULL count of fk_Practice_Site in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_USER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_User IS NULL','NULL count of fk_User in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_DATE_INVOICE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Date_Invoice IS NULL','NULL count of fk_Date_Invoice in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_DATE_DUE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Date_Due IS NULL','NULL count of fk_Date_Due in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_DATE_PAID_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Date_Paid IS NULL','NULL count of fk_Date_Paid in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_INVITEM_DATE_CREATED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND fk_Date_Created IS NULL','NULL count of fk_Date_Created in Gold.Fact_Invoice_Items (tenant 11)',1)
,('GOLD_FKNULL_PAY_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Payments WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Fact_Payments (tenant 11)',1)
,('GOLD_FKNULL_PAY_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Payments WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Fact_Payments (tenant 11)',1)
,('GOLD_FKNULL_PAY_PRACTICE_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Payments WHERE Tenant_ID = 11 AND fk_Practice_Site IS NULL','NULL count of fk_Practice_Site in Gold.Fact_Payments (tenant 11)',1)
,('GOLD_FKNULL_PAY_DATE_PAYMENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Payments WHERE Tenant_ID = 11 AND fk_Date_Payment IS NULL','NULL count of fk_Date_Payment in Gold.Fact_Payments (tenant 11)',1)
,('GOLD_FKNULL_DIARY_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Practitioner_Diaries WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Fact_Practitioner_Diaries (tenant 11)',1)
,('GOLD_FKNULL_DIARY_DATE_DAY_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Practitioner_Diaries WHERE Tenant_ID = 11 AND fk_Date_Day IS NULL','NULL count of fk_Date_Day in Gold.Fact_Practitioner_Diaries (tenant 11)',1)
,('GOLD_FKNULL_NHSCLAIM_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_NHS_Claims WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Fact_NHS_Claims (tenant 11)',1)
,('GOLD_FKNULL_NHSCLAIM_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_NHS_Claims WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Fact_NHS_Claims (tenant 11)',1)
,('GOLD_FKNULL_NHSCLAIM_TREATMENT_PLAN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_NHS_Claims WHERE Tenant_ID = 11 AND fk_Treatment_Plan IS NULL','NULL count of fk_Treatment_Plan in Gold.Fact_NHS_Claims (tenant 11)',1)
,('GOLD_FKNULL_NHSCLAIM_PRACTICE_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_NHS_Claims WHERE Tenant_ID = 11 AND fk_Practice_Site IS NULL','NULL count of fk_Practice_Site in Gold.Fact_NHS_Claims (tenant 11)',1)
,('GOLD_FKNULL_NHSCLAIM_NHS_CONTRACT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_NHS_Claims WHERE Tenant_ID = 11 AND fk_NHS_Contract IS NULL','NULL count of fk_NHS_Contract in Gold.Fact_NHS_Claims (tenant 11)',1)
,('GOLD_FKNULL_NHSCLAIM_DATE_SUBMITTED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_NHS_Claims WHERE Tenant_ID = 11 AND fk_Date_Submitted IS NULL','NULL count of fk_Date_Submitted in Gold.Fact_NHS_Claims (tenant 11)',1)
,('GOLD_FKNULL_NHSCLAIM_DATE_APPROVAL_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_NHS_Claims WHERE Tenant_ID = 11 AND fk_Date_Approval IS NULL','NULL count of fk_Date_Approval in Gold.Fact_NHS_Claims (tenant 11)',1)
,('GOLD_FKNULL_TXAPPT_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Appointments WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Fact_Treatment_Appointments (tenant 11)',1)
,('GOLD_FKNULL_TXAPPT_TREATMENT_PLAN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Appointments WHERE Tenant_ID = 11 AND fk_Treatment_Plan IS NULL','NULL count of fk_Treatment_Plan in Gold.Fact_Treatment_Appointments (tenant 11)',1)
,('GOLD_FKNULL_TXAPPT_DATE_APPOINTMENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Appointments WHERE Tenant_ID = 11 AND fk_Date_Appointment IS NULL','NULL count of fk_Date_Appointment in Gold.Fact_Treatment_Appointments (tenant 11)',1)
,('GOLD_FKNULL_TXAPPT_DATE_CREATED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Appointments WHERE Tenant_ID = 11 AND fk_Date_Created IS NULL','NULL count of fk_Date_Created in Gold.Fact_Treatment_Appointments (tenant 11)',1)
,('GOLD_FKNULL_RECALL_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Fact_Recalls (tenant 11)',1)
,('GOLD_FKNULL_RECALL_DATE_DUE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11 AND fk_Date_Due IS NULL','NULL count of fk_Date_Due in Gold.Fact_Recalls (tenant 11)',1)
,('GOLD_FKNULL_RECALL_DATE_RUN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11 AND fk_Date_Run IS NULL','NULL count of fk_Date_Run in Gold.Fact_Recalls (tenant 11)',1)
,('GOLD_FKNULL_RECALL_DATE_FIRST_REMINDER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11 AND fk_Date_First_Reminder IS NULL','NULL count of fk_Date_First_Reminder in Gold.Fact_Recalls (tenant 11)',1)
,('GOLD_FKNULL_RECALL_DATE_SECOND_REMINDER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11 AND fk_Date_Second_Reminder IS NULL','NULL count of fk_Date_Second_Reminder in Gold.Fact_Recalls (tenant 11)',1)
,('GOLD_FKNULL_RECALL_DATE_LAST_REMINDED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11 AND fk_Date_Last_Reminded IS NULL','NULL count of fk_Date_Last_Reminded in Gold.Fact_Recalls (tenant 11)',1)
,('GOLD_FKNULL_RECALL_DATE_APPT_BOOKED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = 11 AND fk_Date_Appt_Booked IS NULL','NULL count of fk_Date_Appt_Booked in Gold.Fact_Recalls (tenant 11)',1)
,('GOLD_FKNULL_TPI_TREATMENT_PLAN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Treatment_Plan IS NULL','NULL count of fk_Treatment_Plan in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_TPI_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_TPI_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_TPI_PAYMENT_PLAN_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Payment_Plan IS NULL','NULL count of fk_Payment_Plan in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_TPI_TREATMENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Treatment IS NULL','NULL count of fk_Treatment in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_TPI_DATE_CREATED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Date_Created IS NULL','NULL count of fk_Date_Created in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_TPI_DATE_COMPLETED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Date_Completed IS NULL','NULL count of fk_Date_Completed in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_TPI_DATE_UPDATED_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items WHERE Tenant_ID = 11 AND fk_Date_Updated IS NULL','NULL count of fk_Date_Updated in Gold.Fact_Treatment_Plan_Items (tenant 11)',1)
,('GOLD_FKNULL_CONTRACT_PRACTICE_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Contracts WHERE Tenant_ID = 11 AND fk_Practice_Site IS NULL','NULL count of fk_Practice_Site in Gold.Fact_Contracts (tenant 11)',1)
,('GOLD_FKNULL_CONTRACT_DATE_START_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Contracts WHERE Tenant_ID = 11 AND fk_Date_Start IS NULL','NULL count of fk_Date_Start in Gold.Fact_Contracts (tenant 11)',1)
,('GOLD_FKNULL_CONTRACT_DATE_END_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Fact_Contracts WHERE Tenant_ID = 11 AND fk_Date_End IS NULL','NULL count of fk_Date_End in Gold.Fact_Contracts (tenant 11)',1)
,('GOLD_FKNULL_AGGDAILY_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11 AND fk_Site IS NULL','NULL count of fk_Site in Gold.Aggregate_Site_Patient_Practitioner_Daily (tenant 11)',1)
,('GOLD_FKNULL_AGGDAILY_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Aggregate_Site_Patient_Practitioner_Daily (tenant 11)',1)
,('GOLD_FKNULL_AGGDAILY_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Aggregate_Site_Patient_Practitioner_Daily (tenant 11)',1)
,('GOLD_FKNULL_AGGDAILY_DATE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = 11 AND fk_Date IS NULL','NULL count of fk_Date in Gold.Aggregate_Site_Patient_Practitioner_Daily (tenant 11)',1)
,('GOLD_FKNULL_AGGPATCUR_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Patient_Current WHERE Tenant_ID = 11 AND fk_Site IS NULL','NULL count of fk_Site in Gold.Aggregate_Site_Patient_Current (tenant 11)',1)
,('GOLD_FKNULL_AGGPATCUR_PATIENT_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Patient_Current WHERE Tenant_ID = 11 AND fk_Patient IS NULL','NULL count of fk_Patient in Gold.Aggregate_Site_Patient_Current (tenant 11)',1)
,('GOLD_FKNULL_AGGPRACCUR_SITE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Practitioner_Current WHERE Tenant_ID = 11 AND fk_Site IS NULL','NULL count of fk_Site in Gold.Aggregate_Site_Practitioner_Current (tenant 11)',1)
,('GOLD_FKNULL_AGGPRACCUR_PRACTITIONER_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Aggregate_Site_Practitioner_Current WHERE Tenant_ID = 11 AND fk_Practitioner IS NULL','NULL count of fk_Practitioner in Gold.Aggregate_Site_Practitioner_Current (tenant 11)',1)
,('GOLD_FKNULL_DIMPAT_ACQUISITION_SOURCE_T11','FK Null','Gold','count','SELECT COUNT(*) FROM Gold.Dim_Patients WHERE Tenant_ID = 11 AND fk_Acquisition_Source IS NULL','NULL count of fk_Acquisition_Source in Gold.Dim_Patients (tenant 11)',1)
GO

-- =====================================================================
-- Patient cohort metrics (mirror the Patient Cohorts DAX measures).
-- Distinct patients meeting a condition, Tenant 11. Depend on the cohort
-- flags (V001 migration) being applied + Gold reloaded.
-- =====================================================================
INSERT INTO [Test].[Metric_Definition]
    ([Metric_Name], [Metric_Group], [Layer], [Value_Type], [SQL_Text], [Description], [Is_Active])
VALUES
 ('GOLD_PATIENTS_WITH_DISCOUNT_T11','KPI Value','Gold','count','SELECT COUNT(DISTINCT f.fk_Patient) FROM Gold.Fact_Invoice_Items f JOIN Gold.Invoice_Discount d ON d.Tenant_ID = f.Tenant_ID AND d.Invoice_ID = f.Invoice_ID WHERE f.Tenant_ID = 11','Distinct patients with a discounted invoice (positive set)',1)
,('GOLD_PATIENTS_WITH_OUTSTANDING_T11','KPI Value','Gold','count','SELECT COUNT(DISTINCT fk_Patient) FROM Gold.Fact_Invoice_Items WHERE Tenant_ID = 11 AND Is_Invoice_Outstanding = 1','Distinct patients with an outstanding invoice',1)
,('GOLD_PATIENTS_WITH_DEPOSIT_T11','KPI Value','Gold','count','SELECT COUNT(DISTINCT f.fk_Patient) FROM Gold.Fact_Payments f JOIN Gold.Payment_Deposit d ON d.Tenant_ID = f.Tenant_ID AND d.Payment_ID = f.bk_Payment_ID WHERE f.Tenant_ID = 11','Distinct patients who left a deposit (positive set)',1)
,('GOLD_PATIENTS_EMAIL_NOT_CAPTURED_T11','KPI Value','Gold','count','SELECT COUNT(DISTINCT a.fk_Patient) FROM Gold.Fact_Appointments a JOIN Gold.Dim_Patients p ON p.pk_Patient = a.fk_Patient AND p.Tenant_ID = a.Tenant_ID WHERE a.Tenant_ID = 11 AND a.Is_Arrived = 1 AND p.Is_Email_Missing = 1','Distinct attended patients still missing email',1)
,('GOLD_PATIENTS_PHONE_NOT_CAPTURED_T11','KPI Value','Gold','count','SELECT COUNT(DISTINCT a.fk_Patient) FROM Gold.Fact_Appointments a JOIN Gold.Dim_Patients p ON p.pk_Patient = a.fk_Patient AND p.Tenant_ID = a.Tenant_ID WHERE a.Tenant_ID = 11 AND a.Is_Arrived = 1 AND p.Is_Phone_Missing = 1','Distinct attended patients still missing phone',1)
GO
