/* ============================================================================
   DEV ONLY -- targets for Skeleton Group that exercise the roll-up and roll-down rules.

   ==> THIS IS TEST DATA AND IT GUARDS ITSELF. <== It refuses to run anywhere but AppDB-dev, and
   it only ever touches Client_ID = 20 (Skeleton Group). Maple is client 100 and its 525 targets
   are the owner's own, hand-set; the demo is client 11. Neither is touched, and a run against
   AppDB-prod stops at the first statement.

   WHY SKELETON GROUP. It is the only client with a RAGGED hierarchy -- one branch keeps Region,
   Area and Practice, another folded its Area away, a third folded both -- and it had no targets at
   all, so nothing here overwrites a decision anybody made.

        Skeleton Group (Client, key 20)                     9 sites
        |-- North (Region, 7)                               7 sites
        |   |-- Manchester (Area, 9)                        5 sites
        |   |   |-- Skeleton Alpha (Practice, 21)           Alpha Central 10, Alpha North 11
        |   |   \-- Skeleton Bravo (Practice, 22)           Bravo Central 12, East 13, West 14
        |   \-- Skeleton Charlie (Practice, 23)             Charlie Central 15, South 16
        \-- Skeleton Delta (Practice, 24)                   Delta Central 17, Delta West 18

   ==> THE FIGURES ARE CHOSEN SO THAT A WRONG ONE IS OBVIOUS. <== Each entered value has its own
   order of magnitude, so any total on screen can be read back to the leaves that made it. They are
   not plausible dental numbers and are not meant to be.

   WHAT EACH BLOCK PROVES, AND THE ARITHMETIC IT SHOULD PRODUCE:

   A  total_revenue, All Roles, Rolls_Up = 1 -- QUANTITIES ROLL UP.
      Entered at Site for Alpha, Bravo and Delta; at PRACTICE for Charlie, deliberately unequal to
      its own sites, because an entered figure must STOP the roll rather than be overwritten by it.
         Alpha      3,000,000  = 1,000,000 + 2,000,000
         Bravo        435,000  =   400,000 +    30,000 + 5,000
         Manchester 3,435,000  = Alpha + Bravo
         Charlie    9,000,000  = ENTERED. Its sites sum to 770,000 -- that number must NOT appear.
         North     12,435,000  = Manchester + Charlie
         Delta         66,000  =    60,000 +     6,000
         Group     12,501,000  = North + Delta
      Note what is ABSENT: Charlie's practice figure does not apportion down, so Charlie Central
      and Charlie South keep their own entered figures, and a quantity entered at a practice with
      no site figures would leave its sites blank. That is the rule, not a gap.

   B  diary_fill, All Roles, Rolls_Up = 0 -- RATES ROLL DOWN, AND AN OVERRIDE STOPS THEM.
      61 at the client, 72 at Bravo, 83 at one site:
         everything 61, except Bravo and its three sites 72, except Charlie South 83.

   C  revenue_per_dentist_hour, All Roles -- THREE TIERS OF OVERRIDE DOWN ONE BRANCH.
         Group 211, North 232, Manchester 243
         -> Delta and its sites 211 (under the client), Charlie and its sites 232 (under North),
            Alpha, Bravo and their sites 243 (under Manchester).

   D  dna_rate, All Roles, entered ONLY at Area -- A ROLL IS ONE-WAY.
         Manchester 17, Alpha, Bravo and their five sites 17.
         Group, North, Charlie, Delta: nothing at all. A rate does not climb.

   E  total_revenue per ROLE -- ROLES ROLL DOWN ONLY, EVEN FOR A QUANTITY.
         Hygienist 125,000 at the client -> 125,000 at every node. Not 9 x 125,000 anywhere.
         Dentist 310,000 at Alpha and 460,000 at Charlie -> their own sites only. Manchester,
         North and Group show NO Dentist figure: 770,000 would be the bug this proves against.

   F  avg_plan_value per role -- A ROLE RATE, ENTERED MID-TREE.
         Dentist 555 at North -> 555 everywhere under North, except Bravo West 188.

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

/* One row per (node, role, metric); the FY list is crossed on, so both years carry the same
   figure. A rolling twelve-month window straddles two financial years and sums each year's share,
   so equal years keep the window's total equal to the annual target -- otherwise every figure on
   screen would depend on today's date. */
WITH fy(FY) AS (SELECT 2026 UNION ALL SELECT 2027),
seed(Level_Type, Level_Key, Tenant_ID, Target_Level, Metric, Target_Value) AS (
    SELECT * FROM (VALUES
    /* ---- A. quantities roll UP ------------------------------------------------ */
      ('Site',     '10', 21, 'Practice',  'total_revenue',             1000000.00)
    , ('Site',     '11', 21, 'Practice',  'total_revenue',             2000000.00)
    , ('Site',     '12', 22, 'Practice',  'total_revenue',              400000.00)
    , ('Site',     '13', 22, 'Practice',  'total_revenue',               30000.00)
    , ('Site',     '14', 22, 'Practice',  'total_revenue',                5000.00)
    , ('Site',     '15', 23, 'Practice',  'total_revenue',              700000.00)
    , ('Site',     '16', 23, 'Practice',  'total_revenue',               70000.00)
    , ('Practice', '23', 23, 'Practice',  'total_revenue',             9000000.00)  -- stops the roll
    , ('Site',     '17', 24, 'Practice',  'total_revenue',               60000.00)
    , ('Site',     '18', 24, 'Practice',  'total_revenue',                6000.00)

    /* ---- B. a rate rolls DOWN, and an override stops it ------------------------ */
    , ('Client',   '20', 21, 'Practice',  'diary_fill',                     61.00)
    , ('Practice', '22', 22, 'Practice',  'diary_fill',                     72.00)
    , ('Site',     '16', 23, 'Practice',  'diary_fill',                     83.00)

    /* ---- C. three tiers of override down one branch ---------------------------- */
    , ('Client',   '20', 21, 'Practice',  'revenue_per_dentist_hour',      211.00)
    , ('Region',   '7',  21, 'Practice',  'revenue_per_dentist_hour',      232.00)
    , ('Area',     '9',  21, 'Practice',  'revenue_per_dentist_hour',      243.00)

    /* ---- D. entered only at Area: a roll is one-way ---------------------------- */
    , ('Area',     '9',  21, 'Practice',  'dna_rate',                       17.00)

    /* ---- E. roles roll DOWN only, even for a quantity -------------------------- */
    , ('Client',   '20', 21, 'Hygienist', 'total_revenue',              125000.00)
    , ('Practice', '21', 21, 'Dentist',   'total_revenue',              310000.00)
    , ('Practice', '23', 23, 'Dentist',   'total_revenue',              460000.00)

    /* ---- F. a role rate, entered mid-tree -------------------------------------- */
    , ('Region',   '7',  21, 'Dentist',   'avg_plan_value',                555.00)
    , ('Site',     '14', 22, 'Dentist',   'avg_plan_value',                188.00)
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

/* Only the rows this script owns. Client 11's practice-level targets are never in scope -- note
   that a hand-entered Client or Site figure on the demo WOULD be replaced by a re-run. */
DELETE FROM Input.Targets WHERE Client_ID = 11 AND Level_Type IN ('Client', 'Site');
PRINT 'cleared demo client/site rows: ' + CAST(@@ROWCOUNT AS VARCHAR(12)) + ' row(s)';
GO

WITH fy(FY) AS (SELECT 2026 UNION ALL SELECT 2027),
seed(Level_Type, Level_Key, Tenant_ID, Target_Level, Metric, Target_Value) AS (
    SELECT * FROM (VALUES
    /* ---- A. rates at the client: the group view's missing targets ------------- */
      ('Client', '11', 11, 'Practice', 'diary_fill',                    55.00)
    , ('Client', '11', 11, 'Practice', 'revenue_per_dentist_hour',     199.00)
    , ('Client', '11', 11, 'Practice', 'dna_rate',                       9.00)
    , ('Client', '11', 11, 'Practice', 'exam_ratio',                    66.00)
    , ('Client', '11', 11, 'Practice', 'discounts',                      7.00)
    , ('Client', '11', 11, 'Practice', 'deposit_ratio',                 11.00)

    /* ---- B. one site diverges, the other inherits ----------------------------- */
    /*         Demo Practice 2 holds diary_fill 42.65 and rev/dentist hr 158.43.
               George Street takes its own; Stockbridge is deliberately left out. */
    , ('Site',  '8',  12, 'Practice', 'diary_fill',                     88.00)
    , ('Site',  '8',  12, 'Practice', 'revenue_per_dentist_hour',      333.00)

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
