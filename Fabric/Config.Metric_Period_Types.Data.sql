-- Seed data for Config.Metric_Period_Types
-- Defines which period types are valid for each metric, and which is the default
DELETE FROM [Config].[Metric_Period_Types];
GO

INSERT INTO [Config].[Metric_Period_Types]
    ([Metric_Key], [Period_Type], [Is_Default])
VALUES
-- Revenue: both financial year and monthly, default financial year
    ('total_revenue',              'financial_year', 1),
    ('total_revenue',              'monthly',        0),
    ('nhs_revenue',                'financial_year', 1),
    ('nhs_revenue',                'monthly',        0),
    ('private_revenue',            'financial_year', 1),
    ('private_revenue',            'monthly',        0),
    ('revenue_per_patient',        'financial_year', 1),
    ('revenue_per_patient',        'monthly',        0),
    ('revenue_per_hour',           'financial_year', 1),
    ('revenue_per_hour',           'monthly',        0),
    ('deposit_ratio',              'financial_year', 1),
    ('deposit_ratio',              'monthly',        0),

-- Patients: both, default financial year
    ('new_patients',               'financial_year', 1),
    ('new_patients',               'monthly',        0),
    ('active_patients',            'financial_year', 1),
    ('recall_compliance',          'financial_year', 1),
    ('recall_compliance',          'monthly',        0),
    ('patient_retention',          'financial_year', 1),
    ('patient_retention',          'monthly',        0),
    ('recalls_overdue_not_sent',   'monthly',        1),

-- Treatment: both, default financial year
    ('acceptance_rate',            'financial_year', 1),
    ('acceptance_rate',            'monthly',        0),
    ('avg_accepted_value',         'financial_year', 1),
    ('avg_accepted_value',         'monthly',        0),
    ('open_courses',               'monthly',        1),
    ('open_courses_without_appt',  'monthly',        1),
    ('exam_ratio',                 'financial_year', 1),
    ('exam_ratio',                 'monthly',        0),

-- Scheduling: both, default financial year
    ('chair_utilisation',          'financial_year', 1),
    ('chair_utilisation',          'monthly',        0),
    ('dna_rate',                   'financial_year', 1),
    ('dna_rate',                   'monthly',        0),
    ('days_until_30min_free',      'monthly',        1),
    ('days_until_1hr_free',        'monthly',        1),
    ('book_before_you_leave',      'financial_year', 1),
    ('book_before_you_leave',      'monthly',        0),

-- NHS: financial year only (UDA contracts are annual)
    ('uda_delivered',              'financial_year', 1);
GO
