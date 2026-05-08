-- Seed data for Config.Metric_Definitions
-- Metric_Key must match KPI keys used in app.py /api/kpis responses
-- Range_Type: above = higher beats target | below = lower beats target | within = outside variance band is bad
-- Variance: % deviation threshold for 4-way card colouring (NULL = 2-way on/off target only)
DELETE FROM [Config].[Metric_Definitions];
GO

INSERT INTO [Config].[Metric_Definitions]
    ([Metric_Key], [Display_Name], [Section], [Format_Type], [Description],
     [Supports_Site], [Supports_Practitioner], [Is_Active], [Display_Order],
     [Range_Type], [Variance])
VALUES
-- Revenue
    ('total_revenue',              'Total Revenue',                      'revenue',    'currency', 'Combined NHS and private revenue',                                        1, 1, 1, 10, 'above', NULL),
    ('nhs_revenue',                'NHS Revenue',                        'revenue',    'currency', 'Revenue from NHS contracts and claims',                                   1, 1, 1, 11, 'above', NULL),
    ('private_revenue',            'Private Revenue',                    'revenue',    'currency', 'Revenue from private treatment',                                          1, 1, 1, 12, 'above', NULL),
    ('revenue_per_patient',        'Revenue per Patient',                'revenue',    'currency', 'Average revenue generated per active patient',                            1, 1, 1, 13, 'above', NULL),
    ('revenue_per_hour',           'Revenue per Hour',                   'revenue',    'currency', 'Average revenue generated per clinical hour worked',                      1, 1, 1, 14, 'above', NULL),
    ('deposit_ratio',              'Deposit Ratio',                      'revenue',    'percent',  'Percentage of open treatment plan items that have an invoice raised',     1, 1, 1, 15, 'above', NULL),

-- Patients
    ('new_patients',               'New Patients',                       'patients',   'count',    'Number of new patient registrations',                                     1, 1, 1, 20, 'above', NULL),
    ('active_patients',            'Active Patients',                    'patients',   'count',    'Total active patient count',                                              1, 0, 1, 21, 'above', NULL),
    ('recall_compliance',          'Recall Effectiveness',               'patients',   'percent',  'Percentage of due recalls that were attended',                            1, 1, 1, 22, 'above', NULL),
    ('patient_retention',          'Patient Retention',                  'patients',   'percent',  'Percentage of patients who returned within the recall period',            1, 0, 1, 23, 'above', NULL),
    ('recalls_overdue_not_sent',   'Recalls Overdue Not Sent',           'patients',   'percent',  'Percentage of overdue recalls where no recall notice has been sent',      1, 0, 1, 24, 'below', NULL),

-- Treatment
    ('acceptance_rate',            'Treatment Acceptance Rate',          'treatment',  'percent',  'Percentage of presented plans accepted by patients',                      1, 1, 1, 30, 'above', NULL),
    ('open_courses',               'Open Courses',                       'treatment',  'count',    'Number of open courses of treatment',                                     1, 1, 1, 32, 'below', NULL),
    ('open_courses_without_appt',  'Open Courses Without Appointment',   'treatment',  'count',    'Number of open courses with no future appointment booked',               1, 0, 1, 33, 'below', NULL),
    ('exam_ratio',                 'Exam Ratio',                         'treatment',  'percent',  'Percentage of appointments that are examinations',                        1, 1, 1, 34, 'within', NULL),

-- Scheduling
    ('chair_utilisation',          'Chair Utilisation',                  'scheduling', 'percent',  'Percentage of available chair time that was booked',                      1, 1, 1, 40, 'above', NULL),
    ('dna_rate',                   'DNA Rate',                           'scheduling', 'percent',  'Percentage of appointments that were did-not-attend',                     1, 1, 1, 41, 'below', NULL),
    ('days_until_30min_free',      'Days Until Next 30 Minute Free',     'scheduling', 'count',    'Days until the next available 30-minute diary slot for any practitioner', 1, 1, 1, 42, 'below', NULL),
    ('days_until_1hr_free',        'Days Until Next 1 Hour Free',        'scheduling', 'count',    'Days until the next available 1-hour diary slot for any practitioner',    1, 1, 1, 43, 'below', NULL),
    ('book_before_you_leave',      'Book Before You Leave',              'scheduling', 'percent',  'Percentage of completed appointments where a follow-up was booked',       1, 0, 1, 44, 'above', NULL);
GO
