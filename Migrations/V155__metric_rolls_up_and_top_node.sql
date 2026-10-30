-- V155: Rolls_Up on Config.Metric_Definitions, and the two Security columns the top node needs.
--
-- ==> WITHOUT Rolls_Up, Gold.usp_Load_Fact_Node_Targets DOES NOT RUN AT ALL. <== It joins
--     JOIN [Config].[Metric_Definitions] md ON md.Metric_Key = r.Metric AND md.Rolls_Up = 1
-- to decide which metrics roll UP, and reads ISNULL(md.Rolls_Up, 0) = 0 to decide which roll DOWN.
-- The column exists on dev and not on prod -- another one added by hand during development and
-- never written down. Found by diffing the two warehouses rather than by watching the loader fail.
--
-- ==> AND IT CANNOT BE DEFAULTED. <== It is not a flag with a safe neutral value: it decides the
-- DIRECTION a target travels. Default every metric to 0 and no quantity rolls up, so a group shows
-- no total revenue at all; default to 1 and every rate is summed into nonsense -- four practices
-- each targeting 80% diary fill would read 320% at the group. So the values are written out
-- explicitly, exactly as dev holds them.
--
-- 20 metrics roll UP (quantities -- they sum from the leaves):
--     active_patients, days_until_1hr_free, immediate_forward_utilisation, lapsed_calculated,
--     lapsed_deactivated, lapsed_patients, net_patient_growth, new_patients, nhs_revenue,
--     open_courses, open_courses_value, open_courses_without_appt,
--     open_courses_without_appt_value, outstanding_invoices, overdue_recalls,
--     plan_capitation_revenue, private_revenue, recalls_overdue_not_sent, retention_outlook,
--     total_revenue
--
-- 29 roll DOWN (rates and thresholds -- a rate cannot be derived upward from its children):
--     acceptance_rate, avg_first_plan_value, avg_plan_value, book_before_you_leave,
--     cancellation_frequency, cancellation_rebook, chair_utilisation, days_until_30min_free,
--     dentist_recall_conversion, dentist_retention_outlook, deposit_ratio, diary_fill,
--     discounts, dna_rate, email_details_rate, exam_ratio, hygiene_recall_conversion,
--     hygiene_retention_outlook, new_patient_retention, nhs_uda_completion_rate,
--     patient_tracked_in_surgery, phone_details_rate, plan_rejection_rate,
--     post_switch_loss_rate, revenue_per_clinical_hour, revenue_per_dentist_hour,
--     revenue_per_diary_hour, revenue_per_patient, short_notice_cancellation_rate
--
-- A metric added after this migration gets NULL, which ISNULL(...,0) reads as "rolls down". That is
-- the safe direction: a new rate behaves correctly with no action, and a new quantity shows a blank
-- group figure rather than a wrong one.
--
-- The two Security.Application_Users columns are the user's TOP NODE -- the ceiling on what the
-- hierarchy drop-down lets them pick. NULL in both means the client's root, which is exactly
-- today's behaviour, so there is nothing to backfill and no user is affected.
-- Security.vw_User_Tenant_Access also needs its 'Client ID' column; that comes from re-deploying
-- the view, not from here.
--
-- Idempotent: the ALTERs are guarded and the UPDATE is a straight assignment.

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Config' AND TABLE_NAME = 'Metric_Definitions'
                 AND COLUMN_NAME = 'Rolls_Up')
    ALTER TABLE [Config].[Metric_Definitions] ADD [Rolls_Up] BIT NULL;
GO

-- Quantities. Every metric NOT in this list is left NULL, which reads as "rolls down".
UPDATE [Config].[Metric_Definitions]
SET    [Rolls_Up] = 1
WHERE  [Metric_Key] IN (
           'active_patients',
           'days_until_1hr_free',
           'immediate_forward_utilisation',
           'lapsed_calculated',
           'lapsed_deactivated',
           'lapsed_patients',
           'net_patient_growth',
           'new_patients',
           'nhs_revenue',
           'open_courses',
           'open_courses_value',
           'open_courses_without_appt',
           'open_courses_without_appt_value',
           'outstanding_invoices',
           'overdue_recalls',
           'plan_capitation_revenue',
           'private_revenue',
           'recalls_overdue_not_sent',
           'retention_outlook',
           'total_revenue'
       );
GO

UPDATE [Config].[Metric_Definitions]
SET    [Rolls_Up] = 0
WHERE  [Rolls_Up] IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Application_Users'
                 AND COLUMN_NAME = 'Top_Node_Level')
    ALTER TABLE [Security].[Application_Users] ADD [Top_Node_Level] VARCHAR(10) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Application_Users'
                 AND COLUMN_NAME = 'Top_Node_Key')
    ALTER TABLE [Security].[Application_Users] ADD [Top_Node_Key] VARCHAR(64) NULL;
GO

-- ---- prove it, rather than assume it ---------------------------------------
-- The split must match dev exactly: 20 up, 29 down. A different count means a metric key here
-- does not exist in this warehouse's catalogue, and that metric's targets would travel the wrong
-- way with no error anywhere.
SELECT CAST(ISNULL(Rolls_Up, 0) AS INT) AS Rolls_Up, COUNT(*) AS metrics
FROM   [Config].[Metric_Definitions]
GROUP  BY CAST(ISNULL(Rolls_Up, 0) AS INT)
ORDER  BY Rolls_Up DESC;

SELECT 'still NULL' AS check_, COUNT(*) AS metrics
FROM   [Config].[Metric_Definitions] WHERE Rolls_Up IS NULL;

SELECT 'top node columns' AS check_, COUNT(*) AS n
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Application_Users'
  AND  COLUMN_NAME IN ('Top_Node_Level', 'Top_Node_Key');
