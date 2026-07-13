-- Seed data for Config.Metric_Definitions
-- Uses MERGE so existing rows are updated without clearing the table.
-- Range_Type:   above = higher beats target | below = lower beats target | within = outside variance band is bad
-- Target_Type:  cumulative    = accumulates over time; daily apportionment + SUM gives correct prorated target
--               rate          = period-independent ratio/%; target is a fixed threshold at any timescale
--               point_in_time = snapshot value compared against a fixed threshold; daily SUM is meaningless
-- Description       = short, one-line text (tooltip / card).
-- Long_Description  = plain-English definition for the in-product glossary / help panel.
-- Variance is stored per-tenant in Input.Targets, not here.
MERGE [Config].[Metric_Definitions] AS tgt
USING (VALUES
-- Revenue
    ('total_revenue',              'Total Revenue',                      'revenue',    'currency', 'Combined NHS and private revenue',                                        1, 1, 1, 10, 'above', 'cumulative',
        'The combined value of all NHS and private revenue recognised in the period, across every treatment type, site and practitioner. Shown net of discounts. The headline measure of practice income.'),
    ('nhs_revenue',                'NHS Revenue',                        'revenue',    'currency', 'Revenue from NHS contracts and claims',                                   1, 1, 1, 11, 'above', 'cumulative',
        'Revenue earned from NHS activity in the period — the value of NHS claims and contracted UDA/UOA work delivered. Excludes all privately funded treatment. With Private Revenue it makes up Total Revenue.'),
    ('private_revenue',            'Private Revenue',                    'revenue',    'currency', 'Revenue from private treatment',                                          1, 1, 1, 12, 'above', 'cumulative',
        'Revenue from privately funded treatment in the period, including private, care-plan and premium-plan work. Excludes all NHS-funded activity. With NHS Revenue it makes up Total Revenue.'),
    ('revenue_per_patient',        'Revenue per Patient',                'revenue',    'currency', 'Average revenue generated per active patient',                            1, 1, 1, 13, 'above', 'rate',
        'Total revenue in the period divided by the number of active patients — the average value each patient relationship produces. Lets you compare productivity independently of how big the patient base is.'),
    ('revenue_per_clinical_hour',   'Revenue per Clinical Hour',          'revenue',    'currency', 'Revenue per hour of scheduled clinical time (dentists, hygienists, orthodontists, specialists, therapists)', 0, 1, 1, 14, 'above', 'rate',
        'Revenue earned for each hour of scheduled clinical chair time, counting all clinical roles (dentists, hygienists, therapists, orthodontists and specialists). Measures how productively clinical time is used. Revenue per Dentist Hour is the dentist-only equivalent.'),
    ('revenue_per_dentist_hour',   'Revenue per Dentist Hour',           'revenue',    'currency', 'Revenue per hour of scheduled dentist and orthodontist time only',        1, 1, 1, 15, 'above', 'rate',
        'Revenue earned for each hour of scheduled dentist (and orthodontist) chair time only, excluding hygiene and therapy time. A focused view of dentist productivity, complementing the all-clinician Revenue per Clinical Hour.'),
    ('deposit_ratio',              'Deposit Ratio',                      'revenue',    'percent',  'Deposits collected as a percentage of revenue',                           1, 1, 1, 16, 'above', 'point_in_time',
        'The value of deposits taken on treatment plans as a percentage of revenue in the period — money collected up front (e.g. for lab or private work) relative to total income. A higher ratio means more treatment is secured with a deposit before work begins.'),
    ('discounts',                  'Discounts',                          'revenue',    'percent', 'Total discounts applied to invoices (invoice header minus items sum)',    1, 1, 1, 17, 'below', 'rate',
        'The total value of discounts applied to invoices in the period as a percentage of invoiced value, derived from the gap between invoice header totals and the sum of their line items. Lower is better — it shows how much potential income is given away through discounting.'),
    ('outstanding_invoices',       'Outstanding Invoices',               'revenue',    'currency', 'Total value of unpaid invoices', 1, 1, 1, 19, 'below', 'point_in_time',
        'The total value of issued invoices still unpaid as at the reporting date — money owed to the practice by patients and plans. A point-in-time debtor figure; lower is better. Tracks collection performance and cashflow risk.'),
-- Patients
    ('net_patient_growth',         'Net Patient Growth',                 'patients',   'count',    'New patients minus lapsed patients in the period',                        1, 0, 1, 19, 'above', 'cumulative',
        'The net change in the patient base over the period: new patient registrations minus patients who lapsed. Positive means the practice grew its active base; negative means it shrank.'),
    ('new_patients',               'New Patients',                       'patients',   'count',    'Number of new patient registrations', 0, 1, 1, 20, 'above', 'cumulative',
        'The number of new patients who registered with the practice in the period — first-time registrations only. A measure of acquisition and practice growth.'),
    ('active_patients',            'Active Patients',                    'patients',   'count',    'Total active patient count',                                              1, 0, 1, 21, 'above', 'point_in_time',
        'The number of patients currently considered active as at the reporting date — those seen or due within the recall window. A point-in-time count of the live patient base.'),
    ('recalls_overdue_not_sent',   'Recalls Overdue Not Sent',           'patients',   'percent',  'Percentage of overdue recalls where no recall notice has been sent',      1, 0, 1, 24, 'below', 'point_in_time',
        'Of patients whose recall is overdue, the percentage who have not been sent any recall reminder. A process-failure measure — these patients are due back but have had no prompt. Lower is better.'),
    ('retention_outlook',          'Retention Outlook',                  'patients',   'percent',  'Percentage of patients with an active recall who have a future appointment booked', 1, 0, 1, 25, 'above', 'point_in_time',
        'The percentage of patients with an active recall who already have a future appointment booked. A forward-looking retention measure: how much of the recalled patient base is secured to return. Higher is better.'),
    ('lapsed_patients',            'Lapsed Patients',                    'patients',   'count',    'Patients who lapsed in the period (deactivated, or 730+ days since last seen)', 1, 1, 1, 26, 'below', 'cumulative',
        'The number of patients whose 24-month examination clock expired during the period — who passed the point of being considered active without returning. Now a flow metric summed over the period. Lower is better; a measure of attrition.'),
    ('lapsed_deactivated',         'Lapsed (Set Inactive)',              'patients',   'count',    'Patients set inactive (Active=0) in the period',                             1, 1, 1, 27, 'below', 'cumulative',
        'Patients explicitly marked inactive during the period -- the definitive lapsed cohort. Lower is better.'),
    ('lapsed_calculated',          'Lapsed (Silently)',                  'patients',   'count',    'Active patients 730+ days since last seen, in the period',                    1, 1, 1, 28, 'below', 'cumulative',
        'Patients still marked active but 730+ days since their last appointment with no future booking -- silently lapsed. Lower is better.'),
    ('overdue_recalls',            'Overdue Recalls',                    'patients',   'count',    'Number of patients whose recall appointment is overdue',                  1, 0, 1, 27, 'below', 'point_in_time',
        'The number of patients whose recall (re-examination) due date has passed without an appointment booked. A point-in-time backlog of patients overdue to return. Lower is better.'),
    ('email_details_rate',         'Email Details Rate',                 'patients',   'percent',  'Percentage of active patients with a valid email address on file',        1, 0, 1, 28, 'above', 'point_in_time',
        'The percentage of active patients who have a valid email address on file. Higher is better — it underpins recall reminders, marketing and digital communication. A data-quality and reachability measure.'),
    ('phone_details_rate',         'Phone Details Rate',                 'patients',   'percent',  'Percentage of active patients with a valid phone number on file',         1, 0, 1, 29, 'above', 'point_in_time',
        'The percentage of active patients who have a valid phone number on file. Higher is better — it supports appointment reminders and contact. A data-quality and reachability measure.'),
-- Treatment (section now called Clinical in the app)
    ('acceptance_rate',            'Treatment Acceptance Rate',          'treatment',  'percent',  'Percentage of presented plans accepted by patients', 0, 1, 1, 30, 'above', 'rate',
        'The share of treatment presented to patients that they accepted — accepted plan value as a proportion of all plans presented in the period. A measure of treatment conversion and case acceptance. Higher is better.'),
    ('open_courses',               'Open Courses',                       'treatment',  'count',    'Number of open courses of treatment', 0, 1, 1, 32, 'below', 'point_in_time',
        'The number of courses of treatment currently open (started but not completed) as at the reporting date. A point-in-time work-in-progress count; persistently high or rising figures can indicate stalled treatment. Lower is generally better.'),
    ('open_courses_without_appt',  'Open Courses Without Appointment',   'treatment',  'count',    'Number of open courses with no future appointment booked', 0, 1, 1, 33, 'below', 'point_in_time',
        'Of the open courses of treatment, the number with no future appointment booked to continue them. These are at risk of stalling — the patient is mid-treatment with nothing scheduled. Lower is better.'),
    ('open_courses_without_appt_value', 'Open Courses Without Appointment Value', 'treatment', 'currency', 'Total uncharged value of open courses with no future appointment booked', 0, 1, 1, 51, 'below', 'point_in_time',
        'The total price of work still to be charged on open courses of treatment that have no future appointment booked — money committed but not scheduled. The at-risk work-in-progress; lower is better, and converted by booking these patients back in.'),
    ('exam_ratio',                 'Exam Ratio',                         'treatment',  'percent',  'Percentage of appointments that are examinations', 0, 1, 1, 34, 'within', 'rate',
        'The percentage of appointments that are examinations (check-ups) rather than treatment. Judged against a healthy band rather than simply higher or lower — too low may mean under-recall, too high may mean too little treatment delivered.'),
    ('avg_plan_value',             'Average Plan Value',                 'treatment',  'currency', 'Average value of treatment plans presented to patients', 0, 1, 1, 35, 'above', 'rate',
        'The average value of the treatment plans presented to patients in the period — total presented plan value divided by the number of plans. A measure of case size and treatment ambition. Higher generally means larger cases proposed.'),
-- Scheduling
    ('chair_utilisation',          'Chair Utilisation',                  'scheduling', 'percent',  'Percentage of available chair time that was booked', 0, 1, 1, 40, 'above', 'rate',
        'The percentage of available chair (surgery) time that was booked with appointments in the period. A capacity measure of how fully the diary is used. Higher is better, up to practical limits.'),
    ('dna_rate',                   'DNA Rate',                           'scheduling', 'percent',  'Percentage of appointments that were did-not-attend', 0, 1, 1, 41, 'below', 'rate',
        'The percentage of booked appointments where the patient did not attend (DNA) and gave no notice. Represents lost capacity and revenue. Lower is better.'),
    ('days_until_30min_free',      'Days Until Next 30 Minute Free',     'scheduling', 'count',    'Days until the next available 30-minute diary slot for any practitioner', 1, 1, 1, 42, 'below', 'point_in_time',
        'The number of days from today until the next free 30-minute slot in any practitioner''s diary — a measure of short-appointment availability and patient access. Lower is better (shorter waits); a rising number signals the diary is filling up.'),
    ('days_until_1hr_free',        'Days Until Next 1 Hour Free',        'scheduling', 'count',    'Days until the next available 1-hour diary slot for any practitioner',    1, 1, 1, 43, 'below', 'point_in_time',
        'The number of days from today until the next free 1-hour slot in any practitioner''s diary — a measure of availability for longer treatment appointments. Lower is better; a rising number signals constrained capacity.'),
    ('book_before_you_leave',      'Book Before You Leave',              'scheduling', 'percent',  'Percentage of completed appointments where a follow-up was booked', 0, 1, 1, 44, 'above', 'rate',
        'The percentage of completed appointments where the patient left with their next appointment already booked (''book before you leave''). A retention and diary-filling behaviour. Higher is better.'),
    ('cancellation_frequency',     'Cancellation Frequency',             'scheduling', 'percent',  'Percentage of cancelled appointments in the period', 0, 1, 1, 45, 'below', 'rate',
        'The percentage of appointments in the period that were cancelled, at any notice. A measure of diary stability. Lower is better.'),
    ('short_notice_cancellation_rate', 'Short Notice Cancellation Rate', 'scheduling', 'percent',  'Percentage of cancellations that were made with short notice', 0, 1, 1, 46, 'below', 'rate',
        'Of cancelled appointments, the percentage cancelled at short notice — too late to realistically rebook the slot. These are the most damaging cancellations for capacity and revenue. Lower is better.'),
    ('immediate_forward_utilisation', 'Immediate Forward Utilisation', 'scheduling', 'percent', 'Percentage of the next 7 days of chair capacity already booked', 1, 1, 1, 47, 'above', 'point_in_time',
        'The share of available chair time over the next 7 days that is already booked with patient appointments — how full the immediate diary is. A forward-looking capacity measure; higher is better, up to practical limits.'),
-- Home
    ('open_courses_value',         'Open Courses Value',                 'treatment',       'currency', 'Total price of uncharged items on active treatment plans (open courses)', 1, 1, 1, 50, 'above', 'point_in_time',
        'The total price of work still to be charged on active (open) treatment plans as at the reporting date — the uncharged value sitting in work-in-progress. Revenue committed but not yet realised. Higher means more value in the pipeline.'),
 -- NHS
    ('nhs_uda_completion_rate',    'NHS UDA Completion Rate',            'nhs',        'percent',  'UDAs delivered as a percentage of the contracted UDA target',             1, 1, 1, 60, 'within', 'rate',
        'UDAs (Units of Dental Activity) delivered as a percentage of the contracted UDA target, measured against the expected run-rate for the period. Judged against a band — well below risks clawback, well above risks over-delivery without payment. The core NHS contract-performance measure.')
) AS src (
    [Metric_Key], [Display_Name], [Section], [Format_Type], [Description],
    [Supports_Site], [Supports_Practitioner], [Is_Active], [Display_Order], [Range_Type], [Target_Type], [Long_Description]
)
ON tgt.[Metric_Key] = src.[Metric_Key]
WHEN MATCHED THEN UPDATE SET
    tgt.[Display_Name]          = src.[Display_Name],
    tgt.[Section]               = src.[Section],
    tgt.[Format_Type]           = src.[Format_Type],
    tgt.[Description]           = src.[Description],
    tgt.[Long_Description]      = src.[Long_Description],
    tgt.[Supports_Site]         = src.[Supports_Site],
    tgt.[Supports_Practitioner] = src.[Supports_Practitioner],
    tgt.[Is_Active]             = src.[Is_Active],
    tgt.[Display_Order]         = src.[Display_Order],
    tgt.[Range_Type]            = src.[Range_Type],
    tgt.[Target_Type]           = src.[Target_Type]
WHEN NOT MATCHED THEN INSERT (
    [Metric_Key], [Display_Name], [Section], [Format_Type], [Description],
    [Supports_Site], [Supports_Practitioner], [Is_Active], [Display_Order], [Range_Type], [Target_Type], [Long_Description]
) VALUES (
    src.[Metric_Key], src.[Display_Name], src.[Section], src.[Format_Type], src.[Description],
    src.[Supports_Site], src.[Supports_Practitioner], src.[Is_Active], src.[Display_Order], src.[Range_Type], src.[Target_Type], src.[Long_Description]
);
GO

-- ── Post-seed adjustments (2026-07-13) ──────────────────────────────────────
-- (kept out of the MERGE VALUES so the per-metric rows above stay readable.)

-- Cut metrics: removed from the product (dead-end / superseded).
--   revenue_per_dentist_hour = Revenue per Clinical Hour filtered to Practitioner Type = Dentist
--   acceptance_rate          = dead end on real data (Accepted_At NULL on all plans)
--   days_until_1hr_free       = dropped; keep only the 30-minute availability metric
UPDATE [Config].[Metric_Definitions] SET [Is_Active] = 0
    WHERE [Metric_Key] IN ('revenue_per_dentist_hour', 'acceptance_rate', 'days_until_1hr_free');

-- Lapsed sub-cohorts roll up into lapsed_patients -> no SEPARATE target (still active for display).
UPDATE [Config].[Metric_Definitions] SET [Has_Target] = 0
    WHERE [Metric_Key] IN ('lapsed_deactivated', 'lapsed_calculated');

-- NHS Revenue target is derived from the NHS CONTRACT (UDA target x rate), not the
-- manually-entered targets spreadsheet.
UPDATE [Config].[Metric_Definitions] SET [Has_Target] = 0
    WHERE [Metric_Key] = 'nhs_revenue';

-- Exam Ratio target is only meaningful for Dentists -> only generate Dentist practitioner rows.
UPDATE [Config].[Metric_Definitions] SET [Target_Practitioner_Roles] = 'Dentist'
    WHERE [Metric_Key] = 'exam_ratio';
GO
