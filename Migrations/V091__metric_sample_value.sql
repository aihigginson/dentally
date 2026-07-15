-- V091__metric_sample_value.sql
-- Add Config.Metric_Definitions.Sample_Value (a per-metric example for the target grid) via ALTER.
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA='Config' AND TABLE_NAME='Metric_Definitions' AND COLUMN_NAME='Sample_Value')
    EXEC('ALTER TABLE Config.Metric_Definitions ADD Sample_Value VARCHAR(50) NULL');
GO

-- Per-metric sample value (a realistic example shown beside each target box).
UPDATE Config.Metric_Definitions SET Sample_Value = CASE Metric_Key
    WHEN 'total_revenue' THEN '£600,000'
    WHEN 'nhs_revenue' THEN '£150,000'
    WHEN 'private_revenue' THEN '£450,000'
    WHEN 'revenue_per_patient' THEN '£220'
    WHEN 'revenue_per_clinical_hour' THEN '£160'
    WHEN 'revenue_per_dentist_hour' THEN '£220'
    WHEN 'deposit_ratio' THEN '10%'
    WHEN 'discounts' THEN '3%'
    WHEN 'outstanding_invoices' THEN '£15,000'
    WHEN 'net_patient_growth' THEN '300'
    WHEN 'new_patients' THEN '1,200'
    WHEN 'active_patients' THEN '6,000'
    WHEN 'recalls_overdue_not_sent' THEN '5%'
    WHEN 'retention_outlook' THEN '80%'
    WHEN 'dentist_retention_outlook' THEN '80%'
    WHEN 'hygiene_retention_outlook' THEN '75%'
    WHEN 'dentist_recall_conversion' THEN '70%'
    WHEN 'hygiene_recall_conversion' THEN '65%'
    WHEN 'lapsed_patients' THEN '150'
    WHEN 'lapsed_deactivated' THEN '100'
    WHEN 'lapsed_calculated' THEN '50'
    WHEN 'overdue_recalls' THEN '150'
    WHEN 'email_details_rate' THEN '95%'
    WHEN 'phone_details_rate' THEN '97%'
    WHEN 'acceptance_rate' THEN '75%'
    WHEN 'open_courses' THEN '300'
    WHEN 'open_courses_without_appt' THEN '200'
    WHEN 'open_courses_without_appt_value' THEN '£120,000'
    WHEN 'exam_ratio' THEN '55%'
    WHEN 'avg_plan_value' THEN '£850'
    WHEN 'diary_fill' THEN '85%'
    WHEN 'chair_utilisation' THEN '80%'
    WHEN 'dna_rate' THEN '3%'
    WHEN 'days_until_30min_free' THEN '2'
    WHEN 'days_until_1hr_free' THEN '5'
    WHEN 'book_before_you_leave' THEN '70%'
    WHEN 'cancellation_frequency' THEN '8%'
    WHEN 'short_notice_cancellation_rate' THEN '4%'
    WHEN 'immediate_forward_utilisation' THEN '60%'
    WHEN 'patient_tracked_in_surgery' THEN '90%'
    WHEN 'open_courses_value' THEN '£300,000'
    WHEN 'nhs_uda_completion_rate' THEN '95%'
    ELSE Sample_Value END;
GO

-- FTE_Scaled: metric's role/practice target is a FULL-TIME-EQUIVALENT figure; a practitioner's real
-- target = target x their FTE. These are also exempt from the copy-to-blank-roles default.
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA='Config' AND TABLE_NAME='Metric_Definitions' AND COLUMN_NAME='FTE_Scaled')
    EXEC('ALTER TABLE Config.Metric_Definitions ADD FTE_Scaled BIT NULL');
GO
UPDATE Config.Metric_Definitions SET FTE_Scaled = CASE WHEN Metric_Key IN ('total_revenue','nhs_revenue','private_revenue','new_patients','net_patient_growth') THEN 1 ELSE 0 END;
GO

-- Per-practitioner FTE (1.0 = full time) for FTE-scaled target maths. Lives with Associate pay.
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA='Input' AND TABLE_NAME='Practitioner_Pay' AND COLUMN_NAME='FTE')
    EXEC('ALTER TABLE Input.Practitioner_Pay ADD FTE DECIMAL(4,2) NULL');
GO
