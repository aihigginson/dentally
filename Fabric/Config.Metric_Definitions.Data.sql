-- Seed data for Config.Metric_Definitions
-- Metric_Key must match KPI keys used in app.py /api/kpis responses
-- Edit Is_Active, Display_Name, Description as needed; add new rows for future metrics
DELETE FROM [Config].[Metric_Definitions];
GO

INSERT INTO [Config].[Metric_Definitions]
    ([Metric_Key], [Display_Name], [Section], [Format_Type], [Description], [Supports_Site], [Supports_Practitioner], [Is_Active], [Display_Order])
VALUES
-- Revenue
    ('total_revenue',       'Total Revenue',             'revenue',    'currency', 'Combined NHS and private revenue',                     1, 1, 1, 10),
    ('nhs_revenue',         'NHS Revenue',               'revenue',    'currency', 'Revenue from NHS contracts and claims',                1, 1, 1, 11),
    ('private_revenue',     'Private Revenue',           'revenue',    'currency', 'Revenue from private treatment',                       1, 1, 1, 12),
    ('revenue_per_patient', 'Revenue per Patient',       'revenue',    'currency', 'Average revenue generated per active patient',         1, 1, 1, 13),

-- Patients
    ('new_patients',        'New Patients',              'patients',   'count',    'Number of new patient registrations',                  1, 1, 1, 20),
    ('active_patients',     'Active Patients',           'patients',   'count',    'Total active patient count',                           1, 0, 1, 21),
    ('recall_compliance',   'Recall Compliance',         'patients',   'percent',  'Percentage of due recalls that were attended',         1, 1, 1, 22),

-- Treatment
    ('acceptance_rate',     'Treatment Acceptance Rate', 'treatment',  'percent',  'Percentage of presented plans accepted by patients',   1, 1, 1, 30),
    ('avg_accepted_value',  'Avg Accepted Plan Value',   'treatment',  'currency', 'Average value of accepted treatment plans',            1, 1, 1, 31),

-- Scheduling
    ('chair_utilisation',   'Chair Utilisation',         'scheduling', 'percent',  'Percentage of available chair time that was booked',   1, 1, 1, 40),
    ('dna_rate',            'DNA Rate',                  'scheduling', 'percent',  'Percentage of appointments that were did-not-attend',  1, 1, 1, 41),

-- NHS
    ('uda_delivered',       'UDAs Delivered',            'nhs',        'count',    'Number of Units of Dental Activity delivered',         0, 1, 1, 50);
GO
