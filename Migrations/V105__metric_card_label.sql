-- V105__metric_card_label.sql
-- Add Config.Metric_Definitions.Card_Label: short KPI-card label (falls back to Display_Name when
-- NULL). Held on the metric so the PBIR report generator picks it up per metric. ALTER (not table
-- rebuild); Data.sql carries the same UPDATE so a reseed keeps the labels.
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA='Config' AND TABLE_NAME='Metric_Definitions' AND COLUMN_NAME='Card_Label')
    EXEC('ALTER TABLE Config.Metric_Definitions ADD Card_Label VARCHAR(60) NULL');
GO

UPDATE Config.Metric_Definitions SET Card_Label = CASE Metric_Key
    WHEN 'revenue_per_patient'             THEN 'Rev / Patient'
    WHEN 'revenue_per_clinical_hour'       THEN 'Rev / Clinical Hr'
    WHEN 'revenue_per_dentist_hour'        THEN 'Rev / Dentist Hr'
    WHEN 'outstanding_invoices'            THEN 'Outstanding Inv'
    WHEN 'dentist_retention_outlook'       THEN 'Dentist Retention'
    WHEN 'hygiene_retention_outlook'       THEN 'Hygiene Retention'
    WHEN 'dentist_recall_conversion'       THEN 'Dentist Conversion'
    WHEN 'hygiene_recall_conversion'       THEN 'Hygiene Conversion'
    WHEN 'email_details_rate'              THEN 'Email Details'
    WHEN 'phone_details_rate'              THEN 'Phone Details'
    WHEN 'open_courses_without_appt'       THEN 'Open (No Appt)'
    WHEN 'open_courses_without_appt_value' THEN 'Open Courses (No Appt)'
    WHEN 'avg_plan_value'                  THEN 'Avg Plan Value'
    WHEN 'chair_utilisation'               THEN 'Chair Util'
    WHEN 'days_until_30min_free'           THEN 'Days to 30min Free'
    WHEN 'cancellation_frequency'          THEN 'Cancel Frequency'
    WHEN 'short_notice_cancellation_rate'  THEN 'Short Notice Canc'
    WHEN 'patient_tracked_in_surgery'      THEN 'Patient Tracked'
    WHEN 'nhs_uda_completion_rate'         THEN 'UDA Completion'
    WHEN 'book_before_you_leave'           THEN 'Book Before Leave'
    ELSE Card_Label END;
GO
