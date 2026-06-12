-- ============================================================
-- Diagnose_Bronze_FK_Nulls.sql
-- ============================================================
-- Checks every Bronze column that flows into an FK column in
-- Silver / Gold (entity ID FKs and date FKs), and flags any
-- column where ALL rows are NULL in the current test data.
--
-- Static UNION ALL — no dynamic SQL, Fabric-safe.
-- Results ordered: ALL NULL first, empty tables second, OK last.
-- ============================================================

SELECT * FROM (

-- ── Appointments — ID columns ────────────────────────────────
SELECT 'Bronze.Appointments' AS Table_Name, 'Patient_ID' AS Column_Name,
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) AS Null_Count,
    CAST(100.0 * SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,1)) AS Null_Pct,
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END AS Is_All_Null,
    '' AS Note
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Practitioner_ID',
    COUNT(*), SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','User_ID',
    COUNT(*), SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Payment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Room_ID',
    COUNT(*), SUM(CASE WHEN Room_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Room_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Room_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Appointment_Cancellation_Reason_ID',
    COUNT(*), SUM(CASE WHEN Appointment_Cancellation_Reason_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Appointment_Cancellation_Reason_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Appointment_Cancellation_Reason_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL expected for non-cancelled rows'
FROM Bronze.Appointments

-- ── Appointments — date columns ──────────────────────────────
UNION ALL
SELECT 'Bronze.Appointments','Start_Time',
    COUNT(*), SUM(CASE WHEN Start_Time IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Start_Time IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Start_Time IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Finish_Time',
    COUNT(*), SUM(CASE WHEN Finish_Time IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Finish_Time IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Finish_Time IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Arrived_At',
    COUNT(*), SUM(CASE WHEN Arrived_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Arrived_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Arrived_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL for future/cancelled appointments'
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Completed_At',
    COUNT(*), SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL unless attended'
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Cancelled_At',
    COUNT(*), SUM(CASE WHEN Cancelled_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Cancelled_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Cancelled_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL for non-cancelled appointments'
FROM Bronze.Appointments
UNION ALL
SELECT 'Bronze.Appointments','Did_Not_Attend_At',
    COUNT(*), SUM(CASE WHEN Did_Not_Attend_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Did_Not_Attend_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Did_Not_Attend_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL unless DNA'
FROM Bronze.Appointments

-- ── Patients — ID columns ────────────────────────────────────
UNION ALL
SELECT 'Bronze.Patients','Account_ID',
    COUNT(*), SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Acquisition_Source_ID',
    COUNT(*), SUM(CASE WHEN Acquisition_Source_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Acquisition_Source_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Acquisition_Source_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Dentist_ID',
    COUNT(*), SUM(CASE WHEN Dentist_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Dentist_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Dentist_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL if no assigned dentist'
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Hygienist_ID',
    COUNT(*), SUM(CASE WHEN Hygienist_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Hygienist_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Hygienist_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL if no assigned hygienist'
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Payment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Site_ID',
    COUNT(*), SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patients

-- ── Patients — date columns ───────────────────────────────────
UNION ALL
SELECT 'Bronze.Patients','Created_At',
    COUNT(*), SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Date_Of_Birth',
    COUNT(*), SUM(CASE WHEN Date_Of_Birth IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Date_Of_Birth IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Date_Of_Birth IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL if not recorded'
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Dentist_Recall_Date',
    COUNT(*), SUM(CASE WHEN Dentist_Recall_Date IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Dentist_Recall_Date IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Dentist_Recall_Date IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL if no recall set'
FROM Bronze.Patients
UNION ALL
SELECT 'Bronze.Patients','Hygienist_Recall_Date',
    COUNT(*), SUM(CASE WHEN Hygienist_Recall_Date IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Hygienist_Recall_Date IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Hygienist_Recall_Date IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL if no recall set'
FROM Bronze.Patients

-- ── Invoices — ID columns ─────────────────────────────────────
UNION ALL
SELECT 'Bronze.Invoices','Account_ID',
    COUNT(*), SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoices
UNION ALL
SELECT 'Bronze.Invoices','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoices
UNION ALL
SELECT 'Bronze.Invoices','Site_ID',
    COUNT(*), SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoices
UNION ALL
SELECT 'Bronze.Invoices','User_ID',
    COUNT(*), SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoices

-- ── Invoices — date columns ───────────────────────────────────
UNION ALL
SELECT 'Bronze.Invoices','Dated_On',
    COUNT(*), SUM(CASE WHEN Dated_On IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Dated_On IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Dated_On IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoices
UNION ALL
SELECT 'Bronze.Invoices','Paid_On',
    COUNT(*), SUM(CASE WHEN Paid_On IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Paid_On IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Paid_On IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL for unpaid invoices'
FROM Bronze.Invoices

-- ── Invoice_Items — ID columns ────────────────────────────────
UNION ALL
SELECT 'Bronze.Invoice_Items','Invoice_ID',
    COUNT(*), SUM(CASE WHEN Invoice_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Invoice_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Invoice_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoice_Items
UNION ALL
SELECT 'Bronze.Invoice_Items','Practitioner_ID',
    COUNT(*), SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoice_Items
UNION ALL
SELECT 'Bronze.Invoice_Items','Treatment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL for sundry/non-plan items'
FROM Bronze.Invoice_Items
UNION ALL
SELECT 'Bronze.Invoice_Items','User_ID',
    COUNT(*), SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Invoice_Items

-- ── Payments — ID columns ─────────────────────────────────────
UNION ALL
SELECT 'Bronze.Payments','Account_ID',
    COUNT(*), SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Account_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Payments
UNION ALL
SELECT 'Bronze.Payments','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Payments
UNION ALL
SELECT 'Bronze.Payments','Practitioner_ID',
    COUNT(*), SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Payments
UNION ALL
SELECT 'Bronze.Payments','Payment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Payments
UNION ALL
SELECT 'Bronze.Payments','Site_ID',
    COUNT(*), SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Payments
UNION ALL
SELECT 'Bronze.Payments','User_ID',
    COUNT(*), SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Payments

-- ── Payments — date columns ───────────────────────────────────
UNION ALL
SELECT 'Bronze.Payments','Dated_On',
    COUNT(*), SUM(CASE WHEN Dated_On IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Dated_On IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Dated_On IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Payments

-- ── Treatment_Plans — ID columns ──────────────────────────────
UNION ALL
SELECT 'Bronze.Treatment_Plans','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plans
UNION ALL
SELECT 'Bronze.Treatment_Plans','Practitioner_ID',
    COUNT(*), SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plans

-- ── Treatment_Plans — date columns ────────────────────────────
UNION ALL
SELECT 'Bronze.Treatment_Plans','Created_At',
    COUNT(*), SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plans
UNION ALL
SELECT 'Bronze.Treatment_Plans','Start_Date',
    COUNT(*), SUM(CASE WHEN Start_Date IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Start_Date IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Start_Date IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL on draft plans'
FROM Bronze.Treatment_Plans
UNION ALL
SELECT 'Bronze.Treatment_Plans','End_Date',
    COUNT(*), SUM(CASE WHEN End_Date IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN End_Date IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN End_Date IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL on open plans'
FROM Bronze.Treatment_Plans
UNION ALL
SELECT 'Bronze.Treatment_Plans','Completed_At',
    COUNT(*), SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL on open plans'
FROM Bronze.Treatment_Plans

-- ── Treatment_Plan_Items — ID columns ─────────────────────────
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Treatment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plan_Items
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Treatment_ID',
    COUNT(*), SUM(CASE WHEN Treatment_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Treatment_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Treatment_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plan_Items
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plan_Items
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Practitioner_ID',
    COUNT(*), SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plan_Items
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Payment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Payment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plan_Items
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Referrer_ID',
    COUNT(*), SUM(CASE WHEN Referrer_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Referrer_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Referrer_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL for non-referred items'
FROM Bronze.Treatment_Plan_Items

-- ── Treatment_Plan_Items — date columns ───────────────────────
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Created_At',
    COUNT(*), SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Plan_Items
UNION ALL
SELECT 'Bronze.Treatment_Plan_Items','Completed_At',
    COUNT(*), SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Completed_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL on incomplete items'
FROM Bronze.Treatment_Plan_Items

-- ── Treatment_Appointments ────────────────────────────────────
UNION ALL
SELECT 'Bronze.Treatment_Appointments','Appointment_ID',
    COUNT(*), SUM(CASE WHEN Appointment_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Appointment_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Appointment_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Appointments
UNION ALL
SELECT 'Bronze.Treatment_Appointments','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Appointments
UNION ALL
SELECT 'Bronze.Treatment_Appointments','Treatment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Treatment_Appointments

-- ── Recalls ───────────────────────────────────────────────────
UNION ALL
SELECT 'Bronze.Recalls','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Recalls
UNION ALL
SELECT 'Bronze.Recalls','Appointment_ID',
    COUNT(*), SUM(CASE WHEN Appointment_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Appointment_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Appointment_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL until patient books via recall'
FROM Bronze.Recalls
UNION ALL
SELECT 'Bronze.Recalls','Due_Date',
    COUNT(*), SUM(CASE WHEN Due_Date IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Due_Date IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Due_Date IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Recalls
UNION ALL
SELECT 'Bronze.Recalls','First_Reminder_Sent_At',
    COUNT(*), SUM(CASE WHEN First_Reminder_Sent_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN First_Reminder_Sent_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN First_Reminder_Sent_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL if no reminder sent yet'
FROM Bronze.Recalls
UNION ALL
SELECT 'Bronze.Recalls','Second_Reminder_Sent_At',
    COUNT(*), SUM(CASE WHEN Second_Reminder_Sent_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Second_Reminder_Sent_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Second_Reminder_Sent_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL if only one reminder sent'
FROM Bronze.Recalls

-- ── NHS_Claims ────────────────────────────────────────────────
UNION ALL
SELECT 'Bronze.NHS_Claims','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.NHS_Claims
UNION ALL
SELECT 'Bronze.NHS_Claims','Practitioner_ID',
    COUNT(*), SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Practitioner_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.NHS_Claims
UNION ALL
SELECT 'Bronze.NHS_Claims','Contract_ID',
    COUNT(*), SUM(CASE WHEN Contract_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Contract_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Contract_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.NHS_Claims
UNION ALL
SELECT 'Bronze.NHS_Claims','Treatment_Plan_ID',
    COUNT(*), SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Treatment_Plan_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.NHS_Claims
UNION ALL
SELECT 'Bronze.NHS_Claims','Site_ID',
    COUNT(*), SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Site_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.NHS_Claims
UNION ALL
SELECT 'Bronze.NHS_Claims','Submitted_Date',
    COUNT(*), SUM(CASE WHEN Submitted_Date IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Submitted_Date IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Submitted_Date IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.NHS_Claims
UNION ALL
SELECT 'Bronze.NHS_Claims','Approval_Date',
    COUNT(*), SUM(CASE WHEN Approval_Date IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Approval_Date IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Approval_Date IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL for pending/rejected claims'
FROM Bronze.NHS_Claims

-- ── Patient_Referrals ─────────────────────────────────────────
UNION ALL
SELECT 'Bronze.Patient_Referrals','Patient_ID',
    COUNT(*), SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Patient_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patient_Referrals
UNION ALL
SELECT 'Bronze.Patient_Referrals','User_ID',
    COUNT(*), SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN User_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patient_Referrals
UNION ALL
SELECT 'Bronze.Patient_Referrals','Referred_Practitioner_ID',
    COUNT(*), SUM(CASE WHEN Referred_Practitioner_ID IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Referred_Practitioner_ID IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Referred_Practitioner_ID IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END,
    'NULL for external referrals'
FROM Bronze.Patient_Referrals
UNION ALL
SELECT 'Bronze.Patient_Referrals','Created_At',
    COUNT(*), SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END),
    CAST(100.0*SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0) AS DECIMAL(5,1)),
    CASE WHEN COUNT(*)=0 THEN '(empty)' WHEN COUNT(*)=SUM(CASE WHEN Created_At IS NULL THEN 1 ELSE 0 END) THEN 'ALL NULL' ELSE '' END, ''
FROM Bronze.Patient_Referrals

) AS checks
ORDER BY
    CASE Is_All_Null
        WHEN 'ALL NULL' THEN 0
        WHEN '(empty)'  THEN 1
        ELSE                 2
    END,
    Table_Name,
    Column_Name;
