-- Seed data for Config.Metric_Definitions
-- Uses MERGE so existing rows are updated without clearing the table.
-- Range_Type:   above = higher beats target | below = lower beats target | within = outside variance band is bad
-- Target_Type:  cumulative    = accumulates over time; daily apportionment + SUM gives correct prorated target
--               rate          = period-independent ratio/%; target is a fixed threshold at any timescale
--               point_in_time = snapshot value compared against a fixed threshold; daily SUM is meaningless
-- Variance is stored per-tenant in Input.Targets, not here.
MERGE [Config].[Metric_Definitions] AS tgt
USING (VALUES
-- Revenue
    ('total_revenue',              'Total Revenue',                      'revenue',    'currency', 'Combined NHS and private revenue',                                        1, 1, 1, 10, 'above', 'cumulative'),
    ('nhs_revenue',                'NHS Revenue',                        'revenue',    'currency', 'Revenue from NHS contracts and claims',                                   1, 1, 1, 11, 'above', 'cumulative'),
    ('private_revenue',            'Private Revenue',                    'revenue',    'currency', 'Revenue from private treatment',                                          1, 1, 1, 12, 'above', 'cumulative'),
    ('revenue_per_patient',        'Revenue per Patient',                'revenue',    'currency', 'Average revenue generated per active patient',                            1, 1, 1, 13, 'above', 'rate'),
    ('revenue_per_clinical_hour',   'Revenue per Clinical Hour',          'revenue',    'currency', 'Revenue per hour of scheduled clinical time (dentists, hygienists, orthodontists, specialists, therapists)',  1, 1, 1, 14, 'above', 'rate'),
    ('revenue_per_dentist_hour',   'Revenue per Dentist Hour',           'revenue',    'currency', 'Revenue per hour of scheduled dentist and orthodontist time only',        1, 1, 1, 15, 'above', 'rate'),
    ('deposit_ratio',              'Deposit Ratio',                      'revenue',    'percent',  'Percentage of open treatment plan items that have an invoice raised',     1, 1, 1, 16, 'above', 'point_in_time'),
    ('discounts',                  'Discounts',                          'revenue',    'percent', 'Total discounts applied to invoices (invoice header minus items sum)',    1, 1, 1, 17, 'below', 'rate'),
    ('outstanding_invoices',       'Outstanding Invoices',               'revenue',    'currency', 'Total value of unpaid invoices',                                          1, 0, 1, 19, 'below', 'point_in_time'),
-- Patients
    ('net_patient_growth',         'Net Patient Growth',                 'patients',   'count',    'New patients minus lapsed patients in the period',                        1, 0, 1, 19, 'above', 'cumulative'),
    ('new_patients',               'New Patients',                       'patients',   'count',    'Number of new patient registrations',                                     1, 1, 1, 20, 'above', 'cumulative'),
    ('active_patients',            'Active Patients',                    'patients',   'count',    'Total active patient count',                                              1, 0, 1, 21, 'above', 'point_in_time'),
    ('recalls_overdue_not_sent',   'Recalls Overdue Not Sent',           'patients',   'percent',  'Percentage of overdue recalls where no recall notice has been sent',      1, 0, 1, 24, 'below', 'point_in_time'),
    ('retention_outlook',          'Retention Outlook',                  'patients',   'percent',  'Percentage of patients with an active recall who have a future appointment booked', 1, 0, 1, 25, 'above', 'point_in_time'),
    ('lapsed_patients',            'Lapsed Patients',                    'patients',   'count',    'Patients whose 24-month exam clock expired in the period',                1, 0, 1, 26, 'below', 'point_in_time'),
    ('overdue_recalls',            'Overdue Recalls',                    'patients',   'count',    'Number of patients whose recall appointment is overdue',                  1, 0, 1, 27, 'below', 'point_in_time'),
    ('email_details_rate',         'Email Details Rate',                 'patients',   'percent',  'Percentage of active patients with a valid email address on file',        1, 0, 1, 28, 'above', 'point_in_time'),
    ('phone_details_rate',         'Phone Details Rate',                 'patients',   'percent',  'Percentage of active patients with a valid phone number on file',         1, 0, 1, 29, 'above', 'point_in_time'),
-- Treatment (section now called Clinical in the app)
    ('acceptance_rate',            'Treatment Acceptance Rate',          'treatment',  'percent',  'Percentage of presented plans accepted by patients',                      1, 1, 1, 30, 'above', 'rate'),
    ('open_courses',               'Open Courses',                       'treatment',  'count',    'Number of open courses of treatment',                                     1, 1, 1, 32, 'below', 'point_in_time'),
    ('open_courses_without_appt',  'Open Courses Without Appointment',   'treatment',  'count',    'Number of open courses with no future appointment booked',               1, 0, 1, 33, 'below', 'point_in_time'),
    ('exam_ratio',                 'Exam Ratio',                         'treatment',  'percent',  'Percentage of appointments that are examinations',                        1, 1, 1, 34, 'within', 'rate'),
    ('avg_plan_value',             'Average Plan Value',                 'treatment',  'currency', 'Average value of treatment plans presented to patients',                  1, 1, 1, 35, 'above', 'rate'),
-- Scheduling
    ('chair_utilisation',          'Chair Utilisation',                  'scheduling', 'percent',  'Percentage of available chair time that was booked',                      1, 1, 1, 40, 'above', 'rate'),
    ('dna_rate',                   'DNA Rate',                           'scheduling', 'percent',  'Percentage of appointments that were did-not-attend',                     1, 1, 1, 41, 'below', 'rate'),
    ('days_until_30min_free',      'Days Until Next 30 Minute Free',     'scheduling', 'count',    'Days until the next available 30-minute diary slot for any practitioner', 1, 1, 1, 42, 'below', 'point_in_time'),
    ('days_until_1hr_free',        'Days Until Next 1 Hour Free',        'scheduling', 'count',    'Days until the next available 1-hour diary slot for any practitioner',    1, 1, 1, 43, 'below', 'point_in_time'),
    ('book_before_you_leave',      'Book Before You Leave',              'scheduling', 'percent',  'Percentage of completed appointments where a follow-up was booked',       1, 0, 1, 44, 'above', 'rate'),
    ('cancellation_frequency',     'Cancellation Frequency',             'scheduling', 'percent',  'Percentage of cancelled appointments in the period',                    1, 1, 1, 45, 'below', 'rate'),
    ('short_notice_cancellation_rate', 'Short Notice Cancellation Rate', 'scheduling', 'percent',  'Percentage of cancellations that were made with short notice',            1, 1, 1, 46, 'below', 'rate'),
-- Home
    ('open_courses_value',         'Open Courses Value',                 'treatment',       'currency', 'Total price of uncharged items on active treatment plans (open courses)', 1, 1, 1, 50, 'above', 'point_in_time'),
 -- NHS
    ('nhs_uda_completion_rate',    'NHS UDA Completion Rate',            'nhs',        'percent',  'UDAs delivered as a percentage of the contracted UDA target',             1, 1, 1, 60, 'within', 'rate')
) AS src (
    [Metric_Key], [Display_Name], [Section], [Format_Type], [Description],
    [Supports_Site], [Supports_Practitioner], [Is_Active], [Display_Order], [Range_Type], [Target_Type]
)
ON tgt.[Metric_Key] = src.[Metric_Key]
WHEN MATCHED THEN UPDATE SET
    tgt.[Display_Name]          = src.[Display_Name],
    tgt.[Section]               = src.[Section],
    tgt.[Format_Type]           = src.[Format_Type],
    tgt.[Description]           = src.[Description],
    tgt.[Supports_Site]         = src.[Supports_Site],
    tgt.[Supports_Practitioner] = src.[Supports_Practitioner],
    tgt.[Is_Active]             = src.[Is_Active],
    tgt.[Display_Order]         = src.[Display_Order],
    tgt.[Range_Type]            = src.[Range_Type],
    tgt.[Target_Type]           = src.[Target_Type]
WHEN NOT MATCHED THEN INSERT (
    [Metric_Key], [Display_Name], [Section], [Format_Type], [Description],
    [Supports_Site], [Supports_Practitioner], [Is_Active], [Display_Order], [Range_Type], [Target_Type]
) VALUES (
    src.[Metric_Key], src.[Display_Name], src.[Section], src.[Format_Type], src.[Description],
    src.[Supports_Site], src.[Supports_Practitioner], src.[Is_Active], src.[Display_Order], src.[Range_Type], src.[Target_Type]
);
GO

