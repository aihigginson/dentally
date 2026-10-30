/* ============================================================================
   DEV ONLY -- a COMPLETE target set for Skeleton Group, built to exercise both rolls.

   ==> THIS IS TEST DATA AND IT GUARDS ITSELF. <== It refuses to run anywhere but AppDB-dev, and
   part 1 only ever touches Client_ID = 20. Maple is client 100 and its targets are the owner's
   own, hand-set; neither it nor the demo's practice-level figures are touched.

   ==> HOW IT IS BUILT, AND WHY THAT SHAPE. <== A quantity only rolls UP and a ratio only rolls
   DOWN, so there is exactly one level at which each can be entered and still reach every node:

        ratios      at the GROUP, complete      -- 22 metrics, one value each
        aggregations at the SITES, complete     -- 14 metrics x 9 sites
        roles       at the GROUP, complete      -- per FTE, so one figure for the whole client
        then the middle is overridden           -- one metric per level, read independently

   Entered that way every node has a figure for every metric, and nothing is blank because of the
   direction a roll happens to travel.

   ==> SITE WEIGHTS ARE POWERS OF TWO. <== 1, 2, 4 ... 256 across the nine sites. Every subtotal is
   then a distinct sum of distinct bits, so any roll-up on screen decodes uniquely back to the
   leaves that produced it, and a wrong one cannot coincidentally look right:

        Alpha      3   = 1 + 2                   Charlie    96  = 32 + 64
        Bravo     28   = 4 + 8 + 16              North     127  = 31 + 96
        Manchester 31  = 3 + 28                  Delta     384  = 128 + 256
                                                 Group     511  = every site

   multiplied by each metric's base:

--        total_revenue                      site base   1,000  ->  group 511,000
--        private_revenue                    site base     700  ->  group 357,700
--        plan_capitation_revenue            site base     300  ->  group 153,300
--        outstanding_invoices               site base      50  ->  group 25,550
--        open_courses_value                 site base     200  ->  group 102,200
--        open_courses_without_appt_value    site base      80  ->  group 40,880
--        active_patients                    site base      10  ->  group 5,110
--        new_patients                       site base       4  ->  group 2,044
--        net_patient_growth                 site base       1  ->  group 511
--        lapsed_patients                    site base       2  ->  group 1,022
--        overdue_recalls                    site base       3  ->  group 1,533
--        open_courses                       site base       5  ->  group 2,555
--        open_courses_without_appt          site base       2  ->  group 1,022
--        recalls_overdue_not_sent           site base       1  ->  group 511

   ==> THE FIGURES ARE NOT PLAUSIBLE DENTAL NUMBERS AND ARE NOT MEANT TO BE. <== Skeleton Group has
   almost no actuals, so nothing here is comparable to anything; it exists so that the arithmetic of
   the two rolls can be read off the screen.

   ==> ONE THING THE HOME PAGE WILL NOT MATCH EXACTLY. <== A cumulative target is pro-rated per
   WORKING DAY, and a rolling 12-month window does not align with a financial year on weekends and
   bank holidays -- it holds 262 working days against the year's 261. So a 435,000 annual target
   reads 436,667 on a Last 12 Months tile. That is the apportionment working, and it is the same
   arithmetic that makes Last 3 Months come out at roughly a quarter.

   After running: sync, then rebuild the node facts and the period aggregate --
        Meta.usp_Sync_Input_From_AppDB, Gold.usp_Load_Fact_Node_Targets,
        Gold.usp_Load_Aggregate_Period_Targets.
   ============================================================================ */
SET NOCOUNT ON;

IF DB_NAME() <> 'AppDB-dev'
    THROW 51200, 'Seed_Node_Targets_Dev is DEV ONLY. Refusing to run outside AppDB-dev.', 1;
GO

/* Client 20 and nothing else, so a re-run is a clean replacement rather than a merge. */
DELETE FROM Input.Targets WHERE Client_ID = 20;
PRINT 'cleared Skeleton Group: ' + CAST(@@ROWCOUNT AS VARCHAR(12)) + ' row(s)';
GO

/* Both financial years carry the same figure. A rolling twelve-month window straddles two of them
   and sums each year's share, so equal years keep the window independent of today's date --
   otherwise every number on screen would drift as the window moved. */
WITH fy(FY) AS (SELECT 2026 UNION ALL SELECT 2027),
seed(Level_Type, Level_Key, Tenant_ID, Target_Level, Metric, Target_Value) AS (
    SELECT * FROM (VALUES

    /* ---- A. ratios complete at the GROUP -- they roll DOWN, so this is the only level that can
            give every node a value
       ------------------------------------------------------------- */
      ('Client',  '20',  21, 'Practice', 'revenue_per_clinical_hour',               177.00)
    , ('Client',  '20',  21, 'Practice', 'revenue_per_dentist_hour',                211.00)
    , ('Client',  '20',  21, 'Practice', 'deposit_ratio',                            12.00)
    , ('Client',  '20',  21, 'Practice', 'discounts',                                 7.00)
    , ('Client',  '20',  21, 'Practice', 'dentist_retention_outlook',                82.00)
    , ('Client',  '20',  21, 'Practice', 'hygiene_retention_outlook',                86.00)
    , ('Client',  '20',  21, 'Practice', 'dentist_recall_conversion',                68.00)
    , ('Client',  '20',  21, 'Practice', 'hygiene_recall_conversion',                64.00)
    , ('Client',  '20',  21, 'Practice', 'email_details_rate',                       93.00)
    , ('Client',  '20',  21, 'Practice', 'phone_details_rate',                       98.00)
    , ('Client',  '20',  21, 'Practice', 'exam_ratio',                               66.00)
    , ('Client',  '20',  21, 'Practice', 'avg_plan_value',                          143.00)
    , ('Client',  '20',  21, 'Practice', 'diary_fill',                               61.00)
    , ('Client',  '20',  21, 'Practice', 'chair_utilisation',                        58.00)
    , ('Client',  '20',  21, 'Practice', 'dna_rate',                                  9.00)
    , ('Client',  '20',  21, 'Practice', 'days_until_30min_free',                     3.00)
    , ('Client',  '20',  21, 'Practice', 'book_before_you_leave',                    44.00)
    , ('Client',  '20',  21, 'Practice', 'cancellation_frequency',                   22.00)
    , ('Client',  '20',  21, 'Practice', 'short_notice_cancellation_rate',           13.00)
    , ('Client',  '20',  21, 'Practice', 'patient_tracked_in_surgery',               91.00)
    , ('Client',  '20',  21, 'Practice', 'cancellation_rebook',                      77.00)
    , ('Client',  '20',  21, 'Practice', 'nhs_uda_completion_rate',                  97.00)

    /* ---- B. aggregations complete at the SITES -- they roll UP, so the leaves are the only level
            that can give every node above them a value. Weights are powers of two, so every
            subtotal decodes uniquely to the sites that made it
       ------------------------------------------------------------- */
    , ('Site',    '10',  21, 'Practice', 'total_revenue',                          1000.00)
    , ('Site',    '11',  21, 'Practice', 'total_revenue',                          2000.00)
    , ('Site',    '12',  22, 'Practice', 'total_revenue',                          4000.00)
    , ('Site',    '13',  22, 'Practice', 'total_revenue',                          8000.00)
    , ('Site',    '14',  22, 'Practice', 'total_revenue',                         16000.00)
    , ('Site',    '15',  23, 'Practice', 'total_revenue',                         32000.00)
    , ('Site',    '16',  23, 'Practice', 'total_revenue',                         64000.00)
    , ('Site',    '17',  24, 'Practice', 'total_revenue',                        128000.00)
    , ('Site',    '18',  24, 'Practice', 'total_revenue',                        256000.00)
    , ('Site',    '10',  21, 'Practice', 'private_revenue',                         700.00)
    , ('Site',    '11',  21, 'Practice', 'private_revenue',                        1400.00)
    , ('Site',    '12',  22, 'Practice', 'private_revenue',                        2800.00)
    , ('Site',    '13',  22, 'Practice', 'private_revenue',                        5600.00)
    , ('Site',    '14',  22, 'Practice', 'private_revenue',                       11200.00)
    , ('Site',    '15',  23, 'Practice', 'private_revenue',                       22400.00)
    , ('Site',    '16',  23, 'Practice', 'private_revenue',                       44800.00)
    , ('Site',    '17',  24, 'Practice', 'private_revenue',                       89600.00)
    , ('Site',    '18',  24, 'Practice', 'private_revenue',                      179200.00)
    , ('Site',    '10',  21, 'Practice', 'plan_capitation_revenue',                 300.00)
    , ('Site',    '11',  21, 'Practice', 'plan_capitation_revenue',                 600.00)
    , ('Site',    '12',  22, 'Practice', 'plan_capitation_revenue',                1200.00)
    , ('Site',    '13',  22, 'Practice', 'plan_capitation_revenue',                2400.00)
    , ('Site',    '14',  22, 'Practice', 'plan_capitation_revenue',                4800.00)
    , ('Site',    '15',  23, 'Practice', 'plan_capitation_revenue',                9600.00)
    , ('Site',    '16',  23, 'Practice', 'plan_capitation_revenue',               19200.00)
    , ('Site',    '17',  24, 'Practice', 'plan_capitation_revenue',               38400.00)
    , ('Site',    '18',  24, 'Practice', 'plan_capitation_revenue',               76800.00)
    , ('Site',    '10',  21, 'Practice', 'outstanding_invoices',                     50.00)
    , ('Site',    '11',  21, 'Practice', 'outstanding_invoices',                    100.00)
    , ('Site',    '12',  22, 'Practice', 'outstanding_invoices',                    200.00)
    , ('Site',    '13',  22, 'Practice', 'outstanding_invoices',                    400.00)
    , ('Site',    '14',  22, 'Practice', 'outstanding_invoices',                    800.00)
    , ('Site',    '15',  23, 'Practice', 'outstanding_invoices',                   1600.00)
    , ('Site',    '16',  23, 'Practice', 'outstanding_invoices',                   3200.00)
    , ('Site',    '17',  24, 'Practice', 'outstanding_invoices',                   6400.00)
    , ('Site',    '18',  24, 'Practice', 'outstanding_invoices',                  12800.00)
    , ('Site',    '10',  21, 'Practice', 'open_courses_value',                      200.00)
    , ('Site',    '11',  21, 'Practice', 'open_courses_value',                      400.00)
    , ('Site',    '12',  22, 'Practice', 'open_courses_value',                      800.00)
    , ('Site',    '13',  22, 'Practice', 'open_courses_value',                     1600.00)
    , ('Site',    '14',  22, 'Practice', 'open_courses_value',                     3200.00)
    , ('Site',    '15',  23, 'Practice', 'open_courses_value',                     6400.00)
    , ('Site',    '16',  23, 'Practice', 'open_courses_value',                    12800.00)
    , ('Site',    '17',  24, 'Practice', 'open_courses_value',                    25600.00)
    , ('Site',    '18',  24, 'Practice', 'open_courses_value',                    51200.00)
    , ('Site',    '10',  21, 'Practice', 'open_courses_without_appt_value',          80.00)
    , ('Site',    '11',  21, 'Practice', 'open_courses_without_appt_value',         160.00)
    , ('Site',    '12',  22, 'Practice', 'open_courses_without_appt_value',         320.00)
    , ('Site',    '13',  22, 'Practice', 'open_courses_without_appt_value',         640.00)
    , ('Site',    '14',  22, 'Practice', 'open_courses_without_appt_value',        1280.00)
    , ('Site',    '15',  23, 'Practice', 'open_courses_without_appt_value',        2560.00)
    , ('Site',    '16',  23, 'Practice', 'open_courses_without_appt_value',        5120.00)
    , ('Site',    '17',  24, 'Practice', 'open_courses_without_appt_value',       10240.00)
    , ('Site',    '18',  24, 'Practice', 'open_courses_without_appt_value',       20480.00)
    , ('Site',    '10',  21, 'Practice', 'active_patients',                          10.00)
    , ('Site',    '11',  21, 'Practice', 'active_patients',                          20.00)
    , ('Site',    '12',  22, 'Practice', 'active_patients',                          40.00)
    , ('Site',    '13',  22, 'Practice', 'active_patients',                          80.00)
    , ('Site',    '14',  22, 'Practice', 'active_patients',                         160.00)
    , ('Site',    '15',  23, 'Practice', 'active_patients',                         320.00)
    , ('Site',    '16',  23, 'Practice', 'active_patients',                         640.00)
    , ('Site',    '17',  24, 'Practice', 'active_patients',                        1280.00)
    , ('Site',    '18',  24, 'Practice', 'active_patients',                        2560.00)
    , ('Site',    '10',  21, 'Practice', 'new_patients',                              4.00)
    , ('Site',    '11',  21, 'Practice', 'new_patients',                              8.00)
    , ('Site',    '12',  22, 'Practice', 'new_patients',                             16.00)
    , ('Site',    '13',  22, 'Practice', 'new_patients',                             32.00)
    , ('Site',    '14',  22, 'Practice', 'new_patients',                             64.00)
    , ('Site',    '15',  23, 'Practice', 'new_patients',                            128.00)
    , ('Site',    '16',  23, 'Practice', 'new_patients',                            256.00)
    , ('Site',    '17',  24, 'Practice', 'new_patients',                            512.00)
    , ('Site',    '18',  24, 'Practice', 'new_patients',                           1024.00)
    , ('Site',    '10',  21, 'Practice', 'net_patient_growth',                        1.00)
    , ('Site',    '11',  21, 'Practice', 'net_patient_growth',                        2.00)
    , ('Site',    '12',  22, 'Practice', 'net_patient_growth',                        4.00)
    , ('Site',    '13',  22, 'Practice', 'net_patient_growth',                        8.00)
    , ('Site',    '14',  22, 'Practice', 'net_patient_growth',                       16.00)
    , ('Site',    '15',  23, 'Practice', 'net_patient_growth',                       32.00)
    , ('Site',    '16',  23, 'Practice', 'net_patient_growth',                       64.00)
    , ('Site',    '17',  24, 'Practice', 'net_patient_growth',                      128.00)
    , ('Site',    '18',  24, 'Practice', 'net_patient_growth',                      256.00)
    , ('Site',    '10',  21, 'Practice', 'lapsed_patients',                           2.00)
    , ('Site',    '11',  21, 'Practice', 'lapsed_patients',                           4.00)
    , ('Site',    '12',  22, 'Practice', 'lapsed_patients',                           8.00)
    , ('Site',    '13',  22, 'Practice', 'lapsed_patients',                          16.00)
    , ('Site',    '14',  22, 'Practice', 'lapsed_patients',                          32.00)
    , ('Site',    '15',  23, 'Practice', 'lapsed_patients',                          64.00)
    , ('Site',    '16',  23, 'Practice', 'lapsed_patients',                         128.00)
    , ('Site',    '17',  24, 'Practice', 'lapsed_patients',                         256.00)
    , ('Site',    '18',  24, 'Practice', 'lapsed_patients',                         512.00)
    , ('Site',    '10',  21, 'Practice', 'overdue_recalls',                           3.00)
    , ('Site',    '11',  21, 'Practice', 'overdue_recalls',                           6.00)
    , ('Site',    '12',  22, 'Practice', 'overdue_recalls',                          12.00)
    , ('Site',    '13',  22, 'Practice', 'overdue_recalls',                          24.00)
    , ('Site',    '14',  22, 'Practice', 'overdue_recalls',                          48.00)
    , ('Site',    '15',  23, 'Practice', 'overdue_recalls',                          96.00)
    , ('Site',    '16',  23, 'Practice', 'overdue_recalls',                         192.00)
    , ('Site',    '17',  24, 'Practice', 'overdue_recalls',                         384.00)
    , ('Site',    '18',  24, 'Practice', 'overdue_recalls',                         768.00)
    , ('Site',    '10',  21, 'Practice', 'open_courses',                              5.00)
    , ('Site',    '11',  21, 'Practice', 'open_courses',                             10.00)
    , ('Site',    '12',  22, 'Practice', 'open_courses',                             20.00)
    , ('Site',    '13',  22, 'Practice', 'open_courses',                             40.00)
    , ('Site',    '14',  22, 'Practice', 'open_courses',                             80.00)
    , ('Site',    '15',  23, 'Practice', 'open_courses',                            160.00)
    , ('Site',    '16',  23, 'Practice', 'open_courses',                            320.00)
    , ('Site',    '17',  24, 'Practice', 'open_courses',                            640.00)
    , ('Site',    '18',  24, 'Practice', 'open_courses',                           1280.00)
    , ('Site',    '10',  21, 'Practice', 'open_courses_without_appt',                 2.00)
    , ('Site',    '11',  21, 'Practice', 'open_courses_without_appt',                 4.00)
    , ('Site',    '12',  22, 'Practice', 'open_courses_without_appt',                 8.00)
    , ('Site',    '13',  22, 'Practice', 'open_courses_without_appt',                16.00)
    , ('Site',    '14',  22, 'Practice', 'open_courses_without_appt',                32.00)
    , ('Site',    '15',  23, 'Practice', 'open_courses_without_appt',                64.00)
    , ('Site',    '16',  23, 'Practice', 'open_courses_without_appt',               128.00)
    , ('Site',    '17',  24, 'Practice', 'open_courses_without_appt',               256.00)
    , ('Site',    '18',  24, 'Practice', 'open_courses_without_appt',               512.00)
    , ('Site',    '10',  21, 'Practice', 'recalls_overdue_not_sent',                  1.00)
    , ('Site',    '11',  21, 'Practice', 'recalls_overdue_not_sent',                  2.00)
    , ('Site',    '12',  22, 'Practice', 'recalls_overdue_not_sent',                  4.00)
    , ('Site',    '13',  22, 'Practice', 'recalls_overdue_not_sent',                  8.00)
    , ('Site',    '14',  22, 'Practice', 'recalls_overdue_not_sent',                 16.00)
    , ('Site',    '15',  23, 'Practice', 'recalls_overdue_not_sent',                 32.00)
    , ('Site',    '16',  23, 'Practice', 'recalls_overdue_not_sent',                 64.00)
    , ('Site',    '17',  24, 'Practice', 'recalls_overdue_not_sent',                128.00)
    , ('Site',    '18',  24, 'Practice', 'recalls_overdue_not_sent',                256.00)

    /* ---- C. roles at the GROUP -- per FTE, so one figure for the whole client, and it must appear
            UNCHANGED at every node rather than summed
       ------------------------------------------------------------- */
    , ('Client',  '20',  21, 'Dentist',  'avg_plan_value',                          148.00)
    , ('Client',  '20',  21, 'Hygienist', 'avg_plan_value',                          145.00)
    , ('Client',  '20',  21, 'Dentist',  'book_before_you_leave',                    49.00)
    , ('Client',  '20',  21, 'Hygienist', 'book_before_you_leave',                    46.00)
    , ('Client',  '20',  21, 'Dentist',  'chair_utilisation',                        63.00)
    , ('Client',  '20',  21, 'Hygienist', 'chair_utilisation',                        60.00)
    , ('Client',  '20',  21, 'Dentist',  'days_until_30min_free',                     8.00)
    , ('Client',  '20',  21, 'Hygienist', 'days_until_30min_free',                     5.00)
    , ('Client',  '20',  21, 'Dentist',  'deposit_ratio',                            17.00)
    , ('Client',  '20',  21, 'Hygienist', 'deposit_ratio',                            14.00)
    , ('Client',  '20',  21, 'Dentist',  'diary_fill',                               66.00)
    , ('Client',  '20',  21, 'Hygienist', 'diary_fill',                               63.00)
    , ('Client',  '20',  21, 'Dentist',  'discounts',                                12.00)
    , ('Client',  '20',  21, 'Hygienist', 'discounts',                                 9.00)
    , ('Client',  '20',  21, 'Dentist',  'exam_ratio',                               71.00)
    , ('Client',  '20',  21, 'Hygienist', 'exam_ratio',                               68.00)
    , ('Client',  '20',  21, 'Dentist',  'nhs_uda_completion_rate',                 102.00)
    , ('Client',  '20',  21, 'Hygienist', 'nhs_uda_completion_rate',                  99.00)
    , ('Client',  '20',  21, 'Dentist',  'open_courses',                           1500.00)
    , ('Client',  '20',  21, 'Hygienist', 'open_courses',                            500.00)
    , ('Client',  '20',  21, 'Dentist',  'open_courses_value',                    60000.00)
    , ('Client',  '20',  21, 'Hygienist', 'open_courses_value',                    20000.00)
    , ('Client',  '20',  21, 'Dentist',  'open_courses_without_appt',               600.00)
    , ('Client',  '20',  21, 'Hygienist', 'open_courses_without_appt',               200.00)
    , ('Client',  '20',  21, 'Dentist',  'open_courses_without_appt_value',       24000.00)
    , ('Client',  '20',  21, 'Hygienist', 'open_courses_without_appt_value',        8000.00)
    , ('Client',  '20',  21, 'Dentist',  'outstanding_invoices',                  15000.00)
    , ('Client',  '20',  21, 'Hygienist', 'outstanding_invoices',                   5000.00)
    , ('Client',  '20',  21, 'Dentist',  'plan_capitation_revenue',               90000.00)
    , ('Client',  '20',  21, 'Hygienist', 'plan_capitation_revenue',               30000.00)
    , ('Client',  '20',  21, 'Dentist',  'private_revenue',                      210000.00)
    , ('Client',  '20',  21, 'Hygienist', 'private_revenue',                       70000.00)
    , ('Client',  '20',  21, 'Dentist',  'revenue_per_clinical_hour',               182.00)
    , ('Client',  '20',  21, 'Hygienist', 'revenue_per_clinical_hour',               179.00)
    , ('Client',  '20',  21, 'Dentist',  'revenue_per_dentist_hour',                216.00)
    , ('Client',  '20',  21, 'Hygienist', 'revenue_per_dentist_hour',                213.00)
    , ('Client',  '20',  21, 'Dentist',  'total_revenue',                        300000.00)
    , ('Client',  '20',  21, 'Hygienist', 'total_revenue',                        100000.00)

    /* ---- D. and then the middle is overridden, one metric per level so each override can be read
            on its own
       ------------------------------------------------------------- */
    , ('Region',  '7',   21, 'Practice', 'revenue_per_dentist_hour',                232.00)  -- rate, one level below the group
    , ('Area',    '9',   21, 'Practice', 'revenue_per_dentist_hour',                243.00)  -- and again below that -- three tiers on one branch
    , ('Area',    '9',   21, 'Practice', 'dna_rate',                                 17.00)  -- a rate entered at Area and nowhere above it
    , ('Practice', '22',  22, 'Practice', 'diary_fill',                               72.00)  -- rate override at a practice
    , ('Site',    '16',  23, 'Practice', 'diary_fill',                               83.00)  -- and deeper still, at a single site
    , ('Practice', '23',  23, 'Practice', 'total_revenue',                       9000000.00)  -- QUANTITY override: stops the roll-up. Its sites sum to 96,000, which must NOT appear
    , ('Region',  '7',   21, 'Practice', 'active_patients',                        7777.00)  -- QUANTITY override mid-tree: blocks the 1,270 rolling up from below
    , ('Region',  '7',   21, 'Dentist',  'avg_plan_value',                          555.00)  -- a ROLE figure overriding the client s, one level down
    , ('Site',    '14',  22, 'Dentist',  'avg_plan_value',                          188.00)  -- and a role override at a single site
    ) v (Level_Type, Level_Key, Tenant_ID, Target_Level, Metric, Target_Value)
)
INSERT INTO Input.Targets
    (Tenant_ID, Client_ID, FY, Metric, Target_Level, Target_Value,
     Level_Type, Level_Key, Updated_At, Updated_By)
SELECT s.Tenant_ID, 20, f.FY, s.Metric, s.Target_Level, s.Target_Value,
       s.Level_Type, s.Level_Key, SYSUTCDATETIME(), 'seed:dev'
FROM   seed s CROSS JOIN fy f;

PRINT 'seeded Skeleton Group: ' + CAST(@@ROWCOUNT AS VARCHAR(12)) + ' row(s)';
GO

/* ============================================================================
   PART 2 -- the same rules, on the one client that can SHOW them.

   ==> SKELETON GROUP CANNOT REACH THE HOME PAGE, AND THAT IS NOT A TARGETS FAULT. <==
   Gold.usp_Load_Dim_Date_Grouping only builds a date spine for a tenant with 100+ appointments in
   a financial year. Tenants 21-24 have about twenty each in total -- they are structure without
   volume. No spine means no row in Gold.Aggregate_Period_Targets, so nothing renders for them:
   not targets, not actuals. Part 1 is therefore proved in the warehouse and on the Targets
   screens, not on a report.

   Client 11 (Demonstration Practice) is the only client with BOTH a multi-level hierarchy and
   real volume, so the visible demonstration has to live there:

        Demonstration Practice (Client, 11)              3 sites
        |-- Demo Practice 2 (Practice, 12)               2 sites
        |   |-- George Street (Site, 8)
        |   \-- Stockbridge (Site, 9)
        \-- Demonstration Practice (Practice, 11)        1 site, which folded into it

   ==> PURELY ADDITIVE: NOT ONE EXISTING FIGURE MOVES. <== All 480 of client 11's targets are
   Level_Type = 'Practice'. This writes only at Client and Site level, so every practice-level
   number -- which is what the demo screens show -- stays exactly as it is, and still overrides
   anything rolling down onto it.

   WHAT PART 2 FIXES, AS WELL AS DEMONSTRATES: every RATE metric is currently blank at the client
   node. Rates roll down and never up, and client 11's rates have only ever been entered per
   practice -- so the group view has no rate target at all. Entering them at the client is the
   only thing that can fill it.

   A  Client-level rates -> appear at the client node. Both practices hold their own entered
      rates, so the roll stops there: the practice tiles do not change.
   B  George Street overrides, Stockbridge left alone -> the two sites sit side by side, one
      diverging and one inheriting Demo Practice 2's figure. That contrast is the clearest read
      of the rule there is.
   C  Site quantities -> George Street gets total_revenue and active_patients where it had none.
      They must NOT climb: Demo Practice 2 stays 1,595,507.35 and the client stays 3,395,507.35,
      because an entered figure stops a roll-up. If either moves, the stop is broken.
   ============================================================================ */

/* ==> DELETE BY WHAT THIS SCRIPT WROTE, NOT BY WHERE IT WROTE IT. <== This was scoped to
   Level_Type IN ('Client','Site'), which was right while those levels held nothing but this
   script's own rows. Then AppDB.Migration.Roles_Are_Client_Wide.sql moved client 11's six roles to
   Client level, and the next run of this seed deleted 280 rows of the owner's demo role targets
   along with its own -- recoverable only because the warehouse copy happened to be synced in
   between. Updated_By is the honest scope: this script stamps 'seed:dev' and can now only remove
   what it put there. (Part 1 keeps its whole-client DELETE: client 20 is entirely synthetic and
   nobody else writes to it.) */
DELETE FROM Input.Targets
WHERE  Client_ID = 11 AND Level_Type IN ('Client', 'Site') AND Updated_By = 'seed:dev';
PRINT 'cleared demo client/site rows: ' + CAST(@@ROWCOUNT AS VARCHAR(12)) + ' row(s)';
GO

WITH fy(FY) AS (SELECT 2026 UNION ALL SELECT 2027),
seed(Level_Type, Level_Key, Tenant_ID, Target_Level, Metric, Target_Value) AS (
    SELECT * FROM (VALUES
    /* ---- A. EVERY rate at the client: the group view's missing targets --------- */
    /*         One entry per metric whose client tile was blank. A quantity reaches the client by
               rolling up from the practices; a rate cannot, so if nobody enters it at the client
               there is simply no group target -- which is what the demo's Diary Fill, DNA Rate,
               Exam Ratio and a dozen others showed. Each value is distinct, and distinct from the
               practice figures underneath, so any tile can be read back to the level it came from. */
      ('Client', '11', 11, 'Practice', 'diary_fill',                    55.00)
    , ('Client', '11', 11, 'Practice', 'revenue_per_dentist_hour',     199.00)
    , ('Client', '11', 11, 'Practice', 'dna_rate',                       9.00)
    , ('Client', '11', 11, 'Practice', 'exam_ratio',                    66.00)
    , ('Client', '11', 11, 'Practice', 'discounts',                      7.00)
    , ('Client', '11', 11, 'Practice', 'deposit_ratio',                 11.00)
    , ('Client', '11', 11, 'Practice', 'avg_plan_value',               111.00)
    , ('Client', '11', 11, 'Practice', 'revenue_per_clinical_hour',    177.00)
    , ('Client', '11', 11, 'Practice', 'chair_utilisation',             58.00)
    , ('Client', '11', 11, 'Practice', 'book_before_you_leave',         44.00)
    , ('Client', '11', 11, 'Practice', 'cancellation_frequency',        22.00)
    , ('Client', '11', 11, 'Practice', 'cancellation_rebook',           77.00)
    , ('Client', '11', 11, 'Practice', 'short_notice_cancellation_rate',12.00)
    , ('Client', '11', 11, 'Practice', 'patient_tracked_in_surgery',    91.00)
    , ('Client', '11', 11, 'Practice', 'days_until_30min_free',          3.00)
    , ('Client', '11', 11, 'Practice', 'dentist_recall_conversion',     68.00)
    , ('Client', '11', 11, 'Practice', 'hygiene_recall_conversion',     64.00)
    , ('Client', '11', 11, 'Practice', 'dentist_retention_outlook',     82.00)
    , ('Client', '11', 11, 'Practice', 'hygiene_retention_outlook',     86.00)
    , ('Client', '11', 11, 'Practice', 'email_details_rate',            93.00)
    , ('Client', '11', 11, 'Practice', 'phone_details_rate',            98.00)
    , ('Client', '11', 11, 'Practice', 'nhs_uda_completion_rate',       97.00)

    /* ---- B. one site diverges, the other inherits ----------------------------- */
    /*         Demo Practice 2 holds diary_fill 42.65, rev/dentist hr 158.43, exam ratio 73.84,
               email details 95 and rebooked 90. George Street takes its own figure for each;
               Stockbridge is deliberately left out, so the two sites sit side by side -- same
               parent, one overridden and one inheriting. That contrast is the clearest read of
               the roll-down rule there is. */
    , ('Site',  '8',  12, 'Practice', 'diary_fill',                     88.00)
    , ('Site',  '8',  12, 'Practice', 'revenue_per_dentist_hour',      333.00)
    , ('Site',  '8',  12, 'Practice', 'exam_ratio',                    95.00)
    , ('Site',  '8',  12, 'Practice', 'email_details_rate',            60.00)
    , ('Site',  '8',  12, 'Practice', 'cancellation_rebook',           40.00)

    /* ---- C. a site quantity that must not climb ------------------------------- */
    , ('Site',  '8',  12, 'Practice', 'total_revenue',              123456.00)
    , ('Site',  '8',  12, 'Practice', 'active_patients',              4321.00)
    ) v (Level_Type, Level_Key, Tenant_ID, Target_Level, Metric, Target_Value)
)
INSERT INTO Input.Targets
    (Tenant_ID, Client_ID, FY, Metric, Target_Level, Target_Value,
     Level_Type, Level_Key, Updated_At, Updated_By)
SELECT s.Tenant_ID, 11, f.FY, s.Metric, s.Target_Level, s.Target_Value,
       s.Level_Type, s.Level_Key, SYSUTCDATETIME(), 'seed:dev'
FROM   seed s CROSS JOIN fy f;

PRINT 'seeded demo client/site rows: ' + CAST(@@ROWCOUNT AS VARCHAR(12)) + ' row(s)';
GO

/* ---- prove it landed where it was aimed --------------------------------- */
SELECT Client_ID, ISNULL(Level_Type,'(null)') AS Level_Type, COUNT(*) AS rows_,
       COUNT(DISTINCT Metric) AS metrics, COUNT(DISTINCT Target_Level) AS roles
FROM   Input.Targets WHERE Client_ID IN (11, 20)
GROUP  BY Client_ID, Level_Type ORDER BY Client_ID, Level_Type;

/* Maple is the one that must be bit-for-bit untouched: 525 rows, all its own. */
SELECT 'untouched' AS check_, Client_ID, COUNT(*) AS rows_
FROM   Input.Targets WHERE Client_ID NOT IN (20) GROUP BY Client_ID ORDER BY Client_ID;
GO
