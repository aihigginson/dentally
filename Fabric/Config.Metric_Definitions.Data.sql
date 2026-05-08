-- Seed data for Config.Metric_Definitions
-- Metric_Key must match KPI keys used in app.py /api/kpis responses
-- Edit Is_Active, Display_Name, Description as needed; add new rows for future metrics
DELETE FROM [Config].[Metric_Definitions];
GO

INSERT INTO [Config].[Metric_Definitions]
    ([Metric_Key], [Display_Name], [Section], [Format_Type], [Description], [Supports_Site], [Supports_Practitioner], [Is_Active], [Display_Order])
VALUES
-- Revenue
    ('total_revenue',              'Total Revenue',                      'revenue',    'currency', 'Combined NHS and private revenue',                                        1, 1, 1, 10),
    ('nhs_revenue',                'NHS Revenue',                        'revenue',    'currency', 'Revenue from NHS contracts and claims',                                   1, 1, 1, 11),
    ('private_revenue',            'Private Revenue',                    'revenue',    'currency', 'Revenue from private treatment',                                          1, 1, 1, 12),
    ('revenue_per_patient',        'Revenue per Patient',                'revenue',    'currency', 'Average revenue generated per active patient',                            1, 1, 1, 13),
    ('revenue_per_hour',           'Revenue per Hour',                   'revenue',    'currency', 'Average revenue generated per clinical hour worked',                      1, 1, 1, 14),
    ('deposit_ratio',              'Deposit Ratio',                      'revenue',    'percent',  'Percentage of treatment plans that had a deposit taken',                  1, 1, 1, 15),

-- Patients
    ('new_patients',               'New Patients',                       'patients',   'count',    'Number of new patient registrations',                                     1, 1, 1, 20),
    ('active_patients',            'Active Patients',                    'patients',   'count',    'Total active patient count',                                              1, 0, 1, 21),
    ('recall_compliance',          'Recall Effectiveness',               'patients',   'percent',  'Percentage of due recalls that were attended',                            1, 1, 1, 22),
    ('patient_retention',          'Patient Retention',                  'patients',   'percent',  'Percentage of patients who returned within the recall period',            1, 0, 1, 23),
    ('recalls_overdue_not_sent',   'Recalls Overdue Not Sent',           'patients',   'percent',  'Percentage of overdue recalls where no recall notice has been sent',      1, 0, 1, 24),

-- Treatment
    ('acceptance_rate',            'Treatment Acceptance Rate',          'treatment',  'percent',  'Percentage of presented plans accepted by patients',                      1, 1, 1, 30),
    ('open_courses',               'Open Courses',                       'treatment',  'count',    'Number of open courses of treatment with no completed appointment',       1, 1, 1, 32),
    ('open_courses_without_appt',  'Open Courses Without Appointment',   'treatment',  'percent',  'Percentage of open courses with no future appointment booked',           1, 0, 1, 33),
    ('exam_ratio',                 'Exam Ratio',                         'treatment',  'percent',  'Percentage of appointments that are examinations',                        1, 1, 1, 34),

-- Scheduling
    ('chair_utilisation',          'Chair Utilisation',                  'scheduling', 'percent',  'Percentage of available chair time that was booked',                      1, 1, 1, 40),
    ('dna_rate',                   'DNA Rate',                           'scheduling', 'percent',  'Percentage of appointments that were did-not-attend',                     1, 1, 1, 41),
    ('days_until_30min_free',      'Days Until Next 30 Minute Free',     'scheduling', 'count',    'Days until the next available 30-minute diary slot for any practitioner', 1, 1, 1, 42),
    ('days_until_1hr_free',        'Days Until Next 1 Hour Free',        'scheduling', 'count',    'Days until the next available 1-hour diary slot for any practitioner',    1, 1, 1, 43),
    ('book_before_you_leave',      'Book Before You Leave',              'scheduling', 'percent',  'Percentage of completed appointments where a follow-up was booked',       1, 0, 1, 44);
GO
