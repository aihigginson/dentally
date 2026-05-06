-- Seed data for Config.Metric_Period_Types
-- Defines which period types are valid for each metric, and which is the default
DELETE FROM [Config].[Metric_Period_Types];
GO

INSERT INTO [Config].[Metric_Period_Types]
    ([Metric_Key], [Period_Type], [Is_Default])
VALUES
-- Revenue
    ('total_revenue',             'all_time',      1),
    ('total_revenue',             'financial_year', 0),
    ('total_revenue',             'monthly',        0),
    ('nhs_revenue',               'all_time',      1),
    ('nhs_revenue',               'financial_year', 0),
    ('nhs_revenue',               'monthly',        0),
    ('private_revenue',           'all_time',      1),
    ('private_revenue',           'financial_year', 0),
    ('private_revenue',           'monthly',        0),
    ('revenue_per_patient',       'all_time',      1),
    ('revenue_per_patient',       'financial_year', 0),
    ('revenue_per_patient',       'monthly',        0),
    ('revenue_per_hour',          'all_time',      1),
    ('revenue_per_hour',          'financial_year', 0),
    ('revenue_per_hour',          'monthly',        0),
    ('deposit_ratio',             'all_time',      1),
    ('deposit_ratio',             'financial_year', 0),
    ('deposit_ratio',             'monthly',        0),

-- Patients
    ('new_patients',              'all_time',      1),
    ('new_patients',              'financial_year', 0),
    ('new_patients',              'monthly',        0),
    ('active_patients',           'all_time',      1),
    ('active_patients',           'financial_year', 0),
    ('recall_compliance',         'all_time',      1),
    ('recall_compliance',         'financial_year', 0),
    ('recall_compliance',         'monthly',        0),
    ('patient_retention',         'all_time',      1),
    ('patient_retention',         'financial_year', 0),
    ('patient_retention',         'monthly',        0),
    ('recalls_overdue_not_sent',  'all_time',      1),
    ('recalls_overdue_not_sent',  'monthly',        0),

-- Treatment
    ('acceptance_rate',           'all_time',      1),
    ('acceptance_rate',           'financial_year', 0),
    ('acceptance_rate',           'monthly',        0),
    ('avg_accepted_value',        'all_time',      1),
    ('avg_accepted_value',        'financial_year', 0),
    ('avg_accepted_value',        'monthly',        0),
    ('open_courses',              'all_time',      1),
    ('open_courses',              'monthly',        0),
    ('open_courses_without_appt', 'all_time',      1),
    ('open_courses_without_appt', 'monthly',        0),
    ('exam_ratio',                'all_time',      1),
    ('exam_ratio',                'financial_year', 0),
    ('exam_ratio',                'monthly',        0),

-- Scheduling
    ('chair_utilisation',         'all_time',      1),
    ('chair_utilisation',         'financial_year', 0),
    ('chair_utilisation',         'monthly',        0),
    ('dna_rate',                  'all_time',      1),
    ('dna_rate',                  'financial_year', 0),
    ('dna_rate',                  'monthly',        0),
    ('days_until_30min_free',     'all_time',      1),
    ('days_until_30min_free',     'monthly',        0),
    ('days_until_1hr_free',       'all_time',      1),
    ('days_until_1hr_free',       'monthly',        0),
    ('book_before_you_leave',     'all_time',      1),
    ('book_before_you_leave',     'financial_year', 0),
    ('book_before_you_leave',     'monthly',        0),

-- NHS
    ('uda_delivered',             'all_time',      1),
    ('uda_delivered',             'financial_year', 0);
GO
