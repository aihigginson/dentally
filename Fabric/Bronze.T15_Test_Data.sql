-- =============================================================================
-- Bronze.T15_Test_Data.sql
-- Tenant 15: "Dev Test Practice"  — minimal Bronze seed for pipeline testing
-- =============================================================================
-- Scope: 1 site | 2 practitioners | 5 patients | 2 payment plans | 1 NHS contract
--        13 appointments | 9 treatment plans | 14 treatment plan items | 2 cancellation reasons
--        6 invoices | 12 invoice items | 5 payments | 2 NHS claims
--
-- All entity IDs use 15xxx prefix to avoid clashes with T1–14.
-- Revenue data placed in Nov–Dec 2025 (FY 2025/26).
--
-- Expected Revenue Spider values (when viewing Nov–Dec 2025, ~37 working days):
--   Annual targets entered below (all_time): Total=£24K | NHS=£6K | Private=£18K
--   37-day YTD target per practice: ~£3,402  (24000 × 37/261)
--   Per-practitioner share:         ~£1,701
--
--   Practitioner                  | Total  | NHS  | Private | Outstanding
--   Dr Alex NHS  (Prac 15001)     | £2,100 | £500 | £1,600  | £300
--   Dr Beth Private (Prac 15002)  | £1,800 | £0   | £1,800  | £0
--
--   Approximate ratios (actual will vary by exact working day count):
--     Total Revenue:    Dr Alex ~1.24 (norm ~0.62) | Dr Beth ~1.06 (norm ~0.53) | Avg ~0.57
--     NHS Revenue:      Dr Alex ~1.18 (norm ~0.59) | Dr Beth 0 (norm 0)         | Avg ~0.29
--     Private Revenue:  Dr Alex ~1.25 (norm ~0.63) | Dr Beth ~1.41 (norm ~0.71) | Avg ~0.67
--     Outstanding Inv:  Dr Alex 1.00 (norm 0.50)   | Dr Beth 2.00 (norm 1.00)   | Avg 0.75
--     Plan Value:       both sentinel 1.00 (norm 0.50) until plan value data added
--
-- To run after inserting:
--   1. EXEC Silver.usp_Load_All
--   2. EXEC Gold.usp_Load_All (including usp_Load_Aggregate_Site_Patient_Practitioner_Daily)
-- =============================================================================

SET NOCOUNT ON;
GO

-- =============================================================================
-- 1. TENANT
-- =============================================================================

DELETE FROM Audit.Tenants WHERE Tenant_ID = 15;
INSERT INTO Audit.Tenants
    (Tenant_ID, Client_ID, Tenant_Name, API_Base_URL, API_Key, Dentally_Client_ID, Dentally_Secret, Is_Active, Full_Refresh, Last_Loaded_At, Notes)
VALUES
    (15, 3, 'Dev Test Practice', NULL, NULL, NULL, NULL, 1, 0, NULL,
     'Pipeline test tenant — minimal data, not a real practice.');
GO

-- =============================================================================
-- 2. PRACTICE
-- =============================================================================

DELETE FROM Bronze.Practice WHERE Tenant_ID = 15;
INSERT INTO Bronze.Practice
    (Practice_ID, Practice_Name, NHS, Address_Line_1, Town, Postcode,
     Time_Zone, Slug, Tenant_ID, DW_Loaded_At)
VALUES
    ('1500', 'Dev Test Practice', 1, '1 Test Street', 'Testville', 'TE1 1ST',
     'Europe/London', 'dev-test', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 3. SITES
-- =============================================================================

DELETE FROM Bronze.Sites WHERE Tenant_ID = 15;
INSERT INTO Bronze.Sites
    (Site_ID, Name, Nickname, Active, Address_Line_1, Town, Postcode,
     Practice_ID,
     Monday_Open, Monday_Close, Tuesday_Open, Tuesday_Close,
     Wednesday_Open, Wednesday_Close, Thursday_Open, Thursday_Close,
     Friday_Open, Friday_Close,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('1500', 'Dev Test Practice', 'Test', 1, '1 Test Street', 'Testville', 'TE1 1ST',
     '1500',
     '08:00', '18:00', '08:00', '18:00',
     '08:00', '18:00', '08:00', '18:00',
     '08:00', '17:00',
     15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 4. PAYMENT PLANS
-- =============================================================================

DELETE FROM Bronze.Payment_Plans WHERE Tenant_ID = 15;
INSERT INTO Bronze.Payment_Plans
    (Payment_Plan_ID, Payment_Plan_Name, Payment_Plan_Patient_Friendly_Name,
     Payment_Plan_Active, Payment_Plan_Site_ID,
     Exam_Duration, Dentist_Recall_Interval, Hygienist_Recall_Interval,
     Tenant_ID, DW_Loaded_At)
VALUES
    (1500, 'NHS', 'NHS', 1, '1500', 30, 6, 6, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (1501, 'Private', 'Private', 1, '1500', 30, 6, 6, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 5. CONTRACTS  (one NHS contract for Dr Alex NHS)
-- =============================================================================

DELETE FROM Bronze.Contracts WHERE Tenant_ID = 15;
INSERT INTO Bronze.Contracts
    (ID, Active, Contract_Number, Name, Site_ID,
     Start_Date, End_Date,
     Target, UDA_Value,
     UOA_Target, UOA_Value,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('1500', 1, 'T15-NHS-001', 'Dev Test NHS Contract', '1500',
     '2023-04-01', '2027-03-31',
     '100',   -- UDA target per year
     '27.50', -- UDA value £
     '20', '28.00',
     15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 6. USERS
-- =============================================================================

DELETE FROM Bronze.Users WHERE Tenant_ID = 15;
INSERT INTO Bronze.Users
    (ID, First_Name, Last_Name, Title, Role, Permission_Level,
     Email, Practice_ID, Site_ID,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15001, 'Alex',  'NHS',     'Dr',  'dentist',    2, 'alex.nhs@devtest.test',     '1500', '1500',
     '2020-01-01T00:00:00Z', '2025-01-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, 'Beth',  'Private', 'Dr',  'dentist',    2, 'beth.private@devtest.test', '1500', '1500',
     '2020-01-01T00:00:00Z', '2025-01-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 7. PRACTITIONERS
-- =============================================================================

DELETE FROM Bronze.Practitioners WHERE Tenant_ID = 15;
INSERT INTO Bronze.Practitioners
    (Practitioner_ID, User_ID,
     User_First_Name, User_Last_Name, User_Title, User_Role, User_Email,
     Practitioner_Active, Practitioner_Site_ID,
     Practitioner_Default_Contract_ID,
     Practitioner_GDC_Number,
     User_Permission_Level,
     User_Created_At, User_Updated_At,
     Contract_Targets_String,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15001, 15001,
     'Alex', 'NHS', 'Dr', 'dentist', 'alex.nhs@devtest.test',
     1, '1500',
     '1500',           -- NHS contract
     'GDC150001',
     2,
     '2020-01-01T00:00:00Z', '2025-01-01T00:00:00Z',
     '{"1500":{"uda_target":100,"uoa_target":20}}',
     15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, 15002,
     'Beth', 'Private', 'Dr', 'dentist', 'beth.private@devtest.test',
     1, '1500',
     NULL,             -- no NHS contract
     'GDC150002',
     2,
     '2020-01-01T00:00:00Z', '2025-01-01T00:00:00Z',
     NULL,
     15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 8. PATIENTS  (3 under Dr Alex, 2 under Dr Beth)
--    Contact data: 3/5 have email (60%), 4/5 have mobile (80%)
-- =============================================================================

DELETE FROM Bronze.Patients WHERE Tenant_ID = 15;
INSERT INTO Bronze.Patients
    (Patient_ID, First_Name, Last_Name, Title, Gender,
     Date_Of_Birth, Active, Site_ID,
     Dentist_ID, Dentist_Recall_Interval,
     Payment_Plan_ID,
     Acquisition_Source_ID,
     Email_Address, Mobile_Phone,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15001, 'James',   'Smith',   'Mr',  1, '1985-03-15', 1, '1500', 15001, 6, 1501, '1', 'james.smith@devtest.test',  '07700000001', '2020-06-01T00:00:00Z', '2025-10-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, 'Sarah',   'Jones',   'Mrs', 2, '1990-07-22', 1, '1500', 15001, 6, 1500, '2', 'sarah.jones@devtest.test',  '07700000002', '2021-01-15T00:00:00Z', '2025-09-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15003, 'Michael', 'Brown',   'Mr',  1, '1975-11-08', 1, '1500', 15001, 6, 1501, '3', NULL,                        '07700000003', '2019-03-10T00:00:00Z', '2025-11-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15004, 'Emma',    'Wilson',  'Ms',  2, '1992-04-30', 1, '1500', 15002, 6, 1501, '1', 'emma.wilson@devtest.test',  '07700000004', '2022-02-20T00:00:00Z', '2025-10-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15005, 'David',   'Taylor',  'Mr',  1, '1968-09-12', 1, '1500', 15002, 6, 1501, '2', NULL,                        NULL,          '2018-07-05T00:00:00Z', '2025-11-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- New patients added in FY 2025-26 / FY 2026-27 to lift email rate and new patient count
    (15006, 'Olivia',  'Harris',  'Ms',  2, '1995-06-14', 1, '1500', 15001, 6, 1501, '2', 'olivia.harris@devtest.test', '07700000006', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15007, 'Tom',     'Clarke',  'Mr',  1, '1988-02-28', 1, '1500', 15002, 6, 1501, '1', 'tom.clarke@devtest.test',    '07700000007', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15008, 'Priya',   'Patel',   'Mrs', 2, '2000-11-03', 1, '1500', 15001, 6, 1501, '3', 'priya.patel@devtest.test',   '07700000008', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 9. TREATMENT PLANS  (4 per practitioner, mix of open/completed)
-- =============================================================================

DELETE FROM Bronze.Treatment_Plans WHERE Tenant_ID = 15;
INSERT INTO Bronze.Treatment_Plans
    (ID, Patient_ID, Practitioner_ID, Completed,
     Start_Date, End_Date, Completed_At,
     NHS_UDA_Value, NHS_Completed_UDA_Value, Private_Treatment_Value,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- Dr Alex: 2 completed NHS, 1 completed private, 1 open private
    (15001, 15001, 15001, 1, '2025-09-01', '2025-11-15', '2025-11-15T14:00:00Z', 3.0, 3.0, 0,    '2025-09-01T09:00:00Z', '2025-11-15T14:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, 15002, 15001, 1, '2025-10-01', '2025-12-10', '2025-12-10T11:00:00Z', 6.0, 6.0, 0,    '2025-10-01T09:00:00Z', '2025-12-10T11:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15003, 15001, 15001, 1, '2025-10-01', '2025-11-20', '2025-11-20T16:00:00Z', 0,   0,   1600, '2025-10-01T09:00:00Z', '2025-11-20T16:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15004, 15003, 15001, 0, '2025-12-01', NULL,          NULL,                  0,   0,   500,  '2025-12-01T09:00:00Z', '2025-12-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Dr Beth: 2 completed private, 1 open private, 1 open private
    (15005, 15004, 15002, 1, '2025-09-15', '2025-11-10', '2025-11-10T15:00:00Z', 0,   0,   1200, '2025-09-15T09:00:00Z', '2025-11-10T15:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15006, 15005, 15002, 1, '2025-10-15', '2025-12-05', '2025-12-05T10:00:00Z', 0,   0,   600,  '2025-10-15T09:00:00Z', '2025-12-05T10:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15007, 15004, 15002, 0, '2025-11-01', NULL,          NULL,                  0,   0,   800,  '2025-11-01T09:00:00Z', '2025-11-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15008, 15005, 15002, 0, '2025-12-01', NULL,          NULL,                  0,   0,   400,  '2025-12-01T09:00:00Z', '2025-12-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Proposed (no Start_Date): Treatment_Acceptance_Rate = 8/9 = 88.9%
    (15009, 15001, 15001, 0, NULL,          NULL,          NULL,                  0,   0,   800,  '2026-04-01T09:00:00Z', '2026-04-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 10. TREATMENT PLAN ITEMS
-- =============================================================================

DELETE FROM Bronze.Treatment_Plan_Items WHERE Tenant_ID = 15;
INSERT INTO Bronze.Treatment_Plan_Items
    (ID, Treatment_Plan_ID, Patient_ID, Practitioner_ID,
     Nomenclature, NHS_Treatment_Cat, UDA_Band,
     Completed, Completed_At, Charged,
     Price, Appear_On_Invoice,
     Payment_Plan_ID,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- TP 15001 (Dr Alex, NHS Band 2, 3 UDA)
    ('150001', '15001', 15001, 15001, 'Examination',       'examination', '2', 1, '2025-11-01T10:00:00Z', 1, 23.80, 1, 1500, '2025-11-01T09:00:00Z', '2025-11-01T10:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150002', '15001', 15001, 15001, 'Radiograph',        'radiograph',  '2', 1, '2025-11-01T10:00:00Z', 1, 23.80, 1, 1500, '2025-11-01T09:00:00Z', '2025-11-01T10:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15002 (Dr Alex, NHS Band 3, 6 UDA)
    ('150003', '15002', 15002, 15001, 'Crown',             'crown',       '3', 1, '2025-11-15T14:00:00Z', 1, 65.20, 1, 1500, '2025-11-15T09:00:00Z', '2025-11-15T14:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150004', '15002', 15002, 15001, 'Composite Filling', 'composite',   '3', 1, '2025-12-10T11:00:00Z', 1, 65.20, 1, 1500, '2025-12-10T09:00:00Z', '2025-12-10T11:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15003 (Dr Alex, Private)
    ('150005', '15003', 15001, 15001, 'Porcelain Crown',   NULL,          NULL, 1, '2025-10-20T15:00:00Z', 1, 800.00, 1, 1501, '2025-10-20T09:00:00Z', '2025-10-20T15:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150006', '15003', 15001, 15001, 'Composite Veneer',  NULL,          NULL, 1, '2025-11-20T16:00:00Z', 1, 800.00, 1, 1501, '2025-11-20T09:00:00Z', '2025-11-20T16:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15004 (Dr Alex, open private)
    ('150007', '15004', 15003, 15001, 'Implant Consult',   NULL,          NULL, 0, NULL,                   0, 500.00, 0, 1501, '2025-12-01T09:00:00Z', '2025-12-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15005 (Dr Beth, Private completed)
    ('150008', '15005', 15004, 15002, 'Invisalign',        NULL,          NULL, 1, '2025-11-10T15:00:00Z', 1, 1200.00, 1, 1501, '2025-09-15T09:00:00Z', '2025-11-10T15:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15006 (Dr Beth, Private completed)
    ('150009', '15006', 15005, 15002, 'Whitening',         NULL,          NULL, 1, '2025-12-05T10:00:00Z', 1, 600.00, 1, 1501, '2025-10-15T09:00:00Z', '2025-12-05T10:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15007 (Dr Beth, open)
    ('150010', '15007', 15004, 15002, 'Implant Crown',     NULL,          NULL, 0, NULL,                   0, 800.00, 0, 1501, '2025-11-01T09:00:00Z', '2025-11-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15008 (Dr Beth, open)
    ('150011', '15008', 15005, 15002, 'Ceramic Crown',     NULL,          NULL, 0, NULL,                   0, 400.00, 0, 1501, '2025-12-01T09:00:00Z', '2025-12-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150012', '15008', 15005, 15002, 'Exam',              NULL,          NULL, 0, NULL,                   0, 100.00, 0, 1501, '2025-12-01T09:00:00Z', '2025-12-01T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- TP 15007 extra items — linked to discounted invoice 15006 (patient 15004)
    ('150013', '15007', 15004, 15002, 'Hygiene Session',   NULL,          NULL, 0, NULL,                   0, 250.00, 0, 1501, '2025-12-12T09:00:00Z', '2025-12-12T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150014', '15007', 15004, 15002, 'Fluoride Varnish',  NULL,          NULL, 0, NULL,                   0, 150.00, 0, 1501, '2025-12-12T09:00:00Z', '2025-12-12T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 11. APPOINTMENTS  (10 total: 5 Dr Alex, 5 Dr Beth)
--
-- Bronze.Appointments has no Site_ID column — site is derived via Room_ID
-- in the Stage pipeline. For Bronze direct inserts, Room_ID = Site_ID suffices.
-- Is_Cancelled and Is_DNA in Gold are derived from Cancelled_At / Did_Not_Attend_At
-- timestamps (not from State string), so these must be populated here.
-- =============================================================================

DELETE FROM Bronze.Appointments WHERE Tenant_ID = 15;
INSERT INTO Bronze.Appointments
    (ID, Patient_ID, Practitioner_ID, User_ID,
     Room_ID,
     Start_Time, Finish_Time, Duration, State,
     Reason, Payment_Plan_ID,
     Completed_At, Cancelled_At, Did_Not_Attend_At,
     Appointment_Cancellation_Reason_ID,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- Dr Alex (NHS/private mix)
    (15001, 15001, 15001, 15001, '1500', '2025-11-03T09:00:00Z', '2025-11-03T09:30:00Z', 30, 'complete',        'Examination', 1500, '2025-11-03T09:30:00Z', NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, 15002, 15001, 15001, '1500', '2025-11-10T10:00:00Z', '2025-11-10T11:00:00Z', 60, 'complete',        'Crown prep',  1500, '2025-11-10T11:00:00Z', NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15003, 15001, 15001, 15001, '1500', '2025-11-17T14:00:00Z', '2025-11-17T15:30:00Z', 90, 'complete',        'Veneers',     1501, '2025-11-17T15:30:00Z', NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15004, 15003, 15001, 15001, '1500', '2025-12-01T09:00:00Z', '2025-12-01T09:30:00Z', 30, 'cancelled',       'Consult',     1501, NULL,                    '2025-11-30T14:00:00Z', NULL,                    1,    15, CAST(GETUTCDATE() AS datetime2(3))),  -- standard cancellation
    (15005, 15002, 15001, 15001, '1500', '2026-01-15T10:00:00Z', '2026-01-15T11:00:00Z', 60, 'waiting',         'Crown fit',   1500, NULL,                    NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Dr Beth (private only)
    (15006, 15004, 15002, 15002, '1500', '2025-11-05T09:00:00Z', '2025-11-05T10:30:00Z', 90, 'complete',        'Invisalign',  1501, '2025-11-05T10:30:00Z', NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15007, 15005, 15002, 15002, '1500', '2025-11-12T11:00:00Z', '2025-11-12T12:00:00Z', 60, 'complete',        'Whitening',   1501, '2025-11-12T12:00:00Z', NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15008, 15004, 15002, 15002, '1500', '2025-12-03T09:30:00Z', '2025-12-03T10:30:00Z', 60, 'complete',        'Implant',     1501, '2025-12-03T10:30:00Z', NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15009, 15005, 15002, 15002, '1500', '2025-12-10T14:00:00Z', '2025-12-10T14:30:00Z', 30, 'did_not_attend',  'Review',      1501, NULL,                    NULL,                    '2025-12-10T14:00:00Z', NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15010, 15004, 15002, 15002, '1500', '2026-02-10T09:00:00Z', '2026-02-10T10:30:00Z', 90, 'waiting',         'Implant crown',1501, NULL,                   NULL,                    NULL,                    NULL, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 12. TREATMENT APPOINTMENTS  (linking completed appointments to treatment plans)
--
-- Bronze.Treatment_Appointments links Appointment_ID to Treatment_Plan_ID only —
-- there is no Treatment_Plan_Item_ID column at the Bronze layer (items are item-level
-- detail that comes through Stage for API tenants).
-- One row per completed appointment-plan pair; cancelled/DNA/future appointments omitted.
-- =============================================================================

DELETE FROM Bronze.Treatment_Appointments WHERE Tenant_ID = 15;
INSERT INTO Bronze.Treatment_Appointments
    (ID, Appointment_ID, Patient_ID, Treatment_Plan_ID,
     Completed, Completed_At,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('1500001', 15001, 15001, 15001, 1, '2025-11-03T09:30:00Z', '2025-11-03T09:00:00Z', '2025-11-03T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500002', 15002, 15002, 15002, 1, '2025-11-10T11:00:00Z', '2025-11-10T10:00:00Z', '2025-11-10T11:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500003', 15003, 15001, 15003, 1, '2025-11-17T15:30:00Z', '2025-11-17T14:00:00Z', '2025-11-17T15:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500004', 15006, 15004, 15005, 1, '2025-11-05T10:30:00Z', '2025-11-05T09:00:00Z', '2025-11-05T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500005', 15007, 15005, 15006, 1, '2025-11-12T12:00:00Z', '2025-11-12T11:00:00Z', '2025-11-12T12:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500006', 15008, 15004, 15007, 1, '2025-12-03T10:30:00Z', '2025-12-03T09:30:00Z', '2025-12-03T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 13. INVOICES
-- =============================================================================
-- Dr Alex: Invoice 15001 (private, partial outstanding), Invoice 15002 (NHS, paid)
-- Dr Beth: Invoices 15003-15005 (all private, all paid)
-- Outstanding = £300 for Dr Alex → Outstanding Inv ratio = share(£300)/actual(£300) = 1.00
-- Dr Beth outstanding = £0 → returns 2.00 (perfect for lower-is-better with zero fix)
-- =============================================================================

DELETE FROM Bronze.Invoices WHERE Tenant_ID = 15;
INSERT INTO Bronze.Invoices
    (ID, Patient_ID, Site_ID, User_ID,
     Amount, Paid, Amount_Outstanding,
     Dated_On, Due_On, Reference, Paid_On,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- Dr Alex invoices (15001 partially paid — no Paid_On until settled)
    (15001, 15001, '1500', 15001, 1600.00, 1300.00, 300.00, '2025-11-20', '2025-12-20', 'T15-0001', NULL,         '2025-11-20T00:00:00Z', '2025-11-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, 15002, '1500', 15001,  500.00,  500.00,   0.00, '2025-12-10', '2025-12-10', 'T15-0002', '2025-12-10', '2025-12-10T00:00:00Z', '2025-12-10T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Dr Beth invoices
    (15003, 15004, '1500', 15002, 1200.00, 1200.00,   0.00, '2025-11-10', '2025-11-10', 'T15-0003', '2025-11-10', '2025-11-10T00:00:00Z', '2025-11-10T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15004, 15005, '1500', 15002,  600.00,  600.00,   0.00, '2025-12-05', '2025-12-05', 'T15-0004', '2025-12-05', '2025-12-05T00:00:00Z', '2025-12-05T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15005, 15004, '1500', 15002,  600.00,  600.00,   0.00, '2025-12-08', '2025-12-08', 'T15-0005', '2025-12-08', '2025-12-08T00:00:00Z', '2025-12-08T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Discounted invoice: Amount=£500 header vs £400 items = £100 discount
    (15006, 15004, '1500', 15002,  500.00,  500.00,   0.00, '2025-12-12', '2025-12-12', 'T15-0006', '2025-12-12', '2025-12-12T00:00:00Z', '2025-12-12T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 14. INVOICE ITEMS
-- =============================================================================
-- Revenue by Practitioner_ID and NHS_Charge flag:
--   Dr Alex (15001): Private £1,600 (NHS_Charge=0) + NHS £500 (NHS_Charge=1) = £2,100
--   Dr Beth (15002): Private £1,800 (all NHS_Charge=0) = £1,800
-- =============================================================================

DELETE FROM Bronze.Invoice_Items WHERE Tenant_ID = 15;
INSERT INTO Bronze.Invoice_Items
    (ID, Invoice_ID, Practitioner_ID, User_ID,
     Name, Item_Price, Quantity, Total_Price, NHS_Charge,
     Treatment_Plan_ID, Treatment_Plan_Item_ID,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- Invoice 15001: Dr Alex, private items (NHS_Charge=0)
    ('1500001', 15001, 15001, 15001, 'Porcelain Crown',      800.00, 1,  800.00, 0, 15003, '150005', '2025-11-20T00:00:00Z', '2025-11-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500002', 15001, 15001, 15001, 'Composite Veneer',     800.00, 1,  800.00, 0, 15003, '150006', '2025-11-20T00:00:00Z', '2025-11-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Invoice 15002: Dr Alex, NHS items (NHS_Charge=1)
    ('1500003', 15002, 15001, 15001, 'NHS Band 2 Exam',      250.00, 1,  250.00, 1, 15001, '150001', '2025-12-10T00:00:00Z', '2025-12-10T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500004', 15002, 15001, 15001, 'NHS Band 3 Crown',     250.00, 1,  250.00, 1, 15002, '150003', '2025-12-10T00:00:00Z', '2025-12-10T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Invoice 15003: Dr Beth, private
    ('1500005', 15003, 15002, 15002, 'Invisalign Full',     1200.00, 1, 1200.00, 0, 15005, '150008', '2025-11-10T00:00:00Z', '2025-11-10T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Invoice 15004: Dr Beth, private
    ('1500006', 15004, 15002, 15002, 'Teeth Whitening',      600.00, 1,  600.00, 0, 15006, '150009', '2025-12-05T00:00:00Z', '2025-12-05T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Invoice 15005: Dr Beth, private
    ('1500007', 15005, 15002, 15002, 'Implant Crown Consult', 300.00, 1,  300.00, 0, 15007, '150010', '2025-12-08T00:00:00Z', '2025-12-08T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500008', 15005, 15002, 15002, 'Ceramic Crown Prep',   300.00, 1,  300.00, 0, 15008, '150011', '2025-12-08T00:00:00Z', '2025-12-08T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Invoice 15006: items total £400 vs invoice Amount=£500 → £100 discount
    ('1500009', 15006, 15002, 15002, 'Hygiene Appointment',  250.00, 1,  250.00, 0, 15007, '150013', '2025-12-12T00:00:00Z', '2025-12-12T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500010', 15006, 15002, 15002, 'Fluoride Treatment',   150.00, 1,  150.00, 0, 15007, '150014', '2025-12-12T00:00:00Z', '2025-12-12T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 15. PAYMENTS + PAYMENT ALLOCATIONS
-- =============================================================================

DELETE FROM Bronze.Payments WHERE Tenant_ID = 15;
INSERT INTO Bronze.Payments
    (Payment_ID, Patient_ID, Site_ID, User_ID, Practitioner_ID,
     Amount, Amount_Unexplained, Method, Dated_On, Status, Deleted,
     Explanation_Amount, Explanation_Invoice_ID,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15001, 15001, '1500', 15001, 15001, 1300.00, 0, 'card',  '2025-11-20', 'complete', 0, 1300.00, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, 15002, '1500', 15001, 15001,  500.00, 0, 'cash',  '2025-12-10', 'complete', 0,  500.00, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15003, 15004, '1500', 15002, 15002, 1200.00, 0, 'card',  '2025-11-10', 'complete', 0, 1200.00, 15003, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15004, 15005, '1500', 15002, 15002,  600.00, 0, 'card',  '2025-12-08', 'complete', 0,  600.00, 15004, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Deposit payment: fully unallocated → Is_Deposit=1, Deposit_Amount=£400
    (15005, 15003, '1500', 15001, 15001,  400.00, 400.00, 'bank_transfer', '2025-12-01', 'partial', 0, 0.00,   NULL,  15, CAST(GETUTCDATE() AS datetime2(3)));

-- Fix: Invoice 15005 (£600, Patient 15004) and Invoice 15006 (£500, Patient 15004) were missing payments
INSERT INTO Bronze.Payments
    (Payment_ID, Patient_ID, Site_ID, User_ID, Practitioner_ID,
     Amount, Amount_Unexplained, Method, Dated_On, Status, Deleted,
     Explanation_Amount, Explanation_Invoice_ID,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15006, 15004, '1500', 15002, 15002,  600.00, 0, 'card',  '2025-12-08', 'complete', 0,  600.00, 15005, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15007, 15004, '1500', 15002, 15002,  500.00, 0, 'card',  '2025-12-12', 'complete', 0,  500.00, 15006, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

DELETE FROM Bronze.Payment_Allocations WHERE Tenant_ID = 15;
INSERT INTO Bronze.Payment_Allocations
    (ID, Amount, Invoice_Item_ID, Patient_ID,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('15000001', 800.00, '1500001', 15001, '2025-11-20T00:00:00Z', '2025-11-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15000002', 500.00, '1500002', 15001, '2025-11-20T00:00:00Z', '2025-11-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15000003', 250.00, '1500003', 15002, '2025-12-10T00:00:00Z', '2025-12-10T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15000004', 250.00, '1500004', 15002, '2025-12-10T00:00:00Z', '2025-12-10T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));

-- Allocations for Invoice 15005 (items 1500007+1500008, Patient 15004) and Invoice 15006 (items 1500009+1500010)
INSERT INTO Bronze.Payment_Allocations
    (ID, Amount, Invoice_Item_ID, Patient_ID,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('15000005', 300.00, '1500007', 15004, '2025-12-08T00:00:00Z', '2025-12-08T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15000006', 300.00, '1500008', 15004, '2025-12-08T00:00:00Z', '2025-12-08T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15000007', 250.00, '1500009', 15004, '2025-12-12T00:00:00Z', '2025-12-12T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15000008', 150.00, '1500010', 15004, '2025-12-12T00:00:00Z', '2025-12-12T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 16. NHS CLAIMS  (for Dr Alex's NHS treatment plans)
-- =============================================================================

DELETE FROM Bronze.NHS_Claims WHERE Tenant_ID = 15;
INSERT INTO Bronze.NHS_Claims
    (ID, Treatment_Plan_ID, Patient_ID, Practitioner_ID, Site_ID, Contract_ID,
     Claim_Status, UDA_Band, Expected_UDA, Awarded_UDA,
     Patient_Charge,
     Submitted_Date, Approval_Date,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('15001', 15001, 15001, 15001, '1500', '1500', 'approved', 2, 3.0, 3.0, 23.80,
     '2025-11-16', '2025-11-30',
     '2025-11-16T00:00:00Z', '2025-11-30T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15002', 15002, 15002, 15001, '1500', '1500', 'approved', 3, 6.0, 6.0, 65.20,
     '2025-12-11', '2025-12-31',
     '2025-12-11T00:00:00Z', '2025-12-31T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 17. ACQUISITION SOURCES  (minimal — needed to avoid FK errors in Silver)
-- =============================================================================

DELETE FROM Bronze.Acquisition_Sources WHERE Tenant_ID = 15;
INSERT INTO Bronze.Acquisition_Sources
    (ID, Name, Active, Tenant_ID, DW_Loaded_At)
VALUES
    (1, 'Word of Mouth', 1, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (2, 'Google',        1, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (3, 'Walk In',       1, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 18. INPUT.TARGETS  — loaded from spreadsheets via the Analytically UI
-- =============================================================================
-- Targets for T15 are loaded from:
--   Targets/T15_2025-26.xlsx
--   Targets/T15_2026-27.xlsx
-- NHS UDA / UOA targets are derived automatically from Bronze.Contracts
-- by Gold.usp_Load_Fact_Daily_Targets (no manual entry required).
-- =============================================================================
GO

-- =============================================================================
-- 19. PATIENT STATS  (drives New Patients, Lapsed Patients, Active/Retained)
--
-- First_Appointment_Date → New_Patient flag in Aggregate_Site_Patient_Practitioner_Daily
-- Last_Exam_Date         → Lapsed_Patients DAX (EDATE +24m in window)
-- Next_Appointment_Date  → Future_Appointment flag in Aggregate_Site_Patient_Current
--
-- Patients 15001 + 15004 → new in Nov 2025 (First_Appointment_Date in period)
-- Patient  15003          → last exam Nov 2023 → lapses Nov 2025
-- Patient  15005          → last exam Dec 2023 → lapses Dec 2025
-- Patients 15001 + 15004 → have future recall appointments (Jun 2026)
-- =============================================================================

DELETE FROM Bronze.Patient_Stats WHERE Tenant_ID = 15;
INSERT INTO Bronze.Patient_Stats
    (Patient_ID, First_Appointment_Date, First_Exam_Date,
     Last_Appointment_Date, Last_Exam_Date, Last_Scale_And_Polish_Date,
     Next_Appointment_Date, Next_Exam_Date, Next_Scale_And_Polish_Date,
     Last_FTA_Appointment_Date, Last_Cancelled_Appointment_Date,
     Total_Paid, Total_Invoiced,
     NHS_Exemption_Code,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15001, '2025-11-03', '2025-11-03', '2025-11-17', '2025-11-03', '2025-11-03', '2026-06-15', NULL, NULL, NULL, NULL, 1300.00, 1600.00, NULL, '2020-06-01T00:00:00Z', '2026-05-22T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15002, '2020-03-15', '2020-03-15', '2026-01-15', '2025-11-10', '2025-11-10', NULL,          NULL, NULL, NULL, NULL,  500.00,  500.00, NULL, '2021-01-15T00:00:00Z', '2026-05-22T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15003, '2019-05-20', '2019-05-20', '2025-11-17', '2023-11-20', '2023-11-20', NULL,          NULL, NULL, NULL, NULL,    0.00,    0.00, NULL, '2019-03-10T00:00:00Z', '2026-05-22T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15004, '2025-11-05', '2025-11-05', '2025-12-03', '2025-11-05', '2025-11-05', '2026-06-22', NULL, NULL, NULL, NULL, 1200.00, 1200.00, NULL, '2022-02-20T00:00:00Z', '2026-05-22T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15005, '2018-09-01', '2018-09-01', '2025-12-10', '2023-12-01', '2023-12-01', NULL,          NULL, NULL, NULL, NULL,    0.00,  600.00, NULL, '2018-07-05T00:00:00Z', '2026-05-22T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 20. RECALLS  (4 in-scope records; 2 overdue + unbooked, 2 overdue + booked)
--
-- Is_In_Scope (Gold): Due_Date within [-24m, +1m] of ETL run OR reminder sent.
-- Is_Booked (Gold):   patient has a future non-cancelled appointment at ETL time.
--   Patients 15001 + 15004 → future recall appointments added in section 22 → Is_Booked = 1
--   Patients 15003 + 15005 → no future appointments                          → Is_Booked = 0
--
-- Expected outcomes (today = 2026-05-22):
--   Overdue Recalls          = 2  (15003 + 15005, in-scope + not booked)
--   Retention Outlook        = 2/4 = 50%
--   Recall Effectiveness     = 4/4 = 100% (all have reminders sent)
--   Recalls Overdue Not Sent = 0/4 = 0%   (all have been contacted)
-- =============================================================================

DELETE FROM Bronze.Recalls WHERE Tenant_ID = 15;
INSERT INTO Bronze.Recalls
    (ID, Patient_ID, Recall_Type, Recall_Method, Status,
     Due_Date, First_Reminder_Sent_At, First_Reminder_Type,
     Times_Contacted, Run_Date,
     Workflow_Status,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('15001', 15001, 'dentist',   'sms', 'open', '2026-05-15', '2026-04-15T09:00:00Z', 'sms', 1, '2026-04-15', 'sent', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15002', 15004, 'hygienist', 'sms', 'open', '2026-05-10', '2026-04-10T09:00:00Z', 'sms', 1, '2026-04-10', 'sent', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15003', 15003, 'dentist',   'sms', 'open', '2025-11-20', '2025-10-20T09:00:00Z', 'sms', 2, '2025-10-20', 'sent', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('15004', 15005, 'hygienist', 'sms', 'open', '2026-01-01', '2025-12-01T09:00:00Z', 'sms', 1, '2025-12-01', 'sent', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 21. PRACTITIONER DIARY
--
-- Unavailable = 0 means the session IS available (Silver inverts to Available=1).
-- 09:00-17:00 = 480 mins; no breaks added → Available_Clinical_Mins = 480.
--
-- Past entries: match each appointment date so Chair Utilisation has a denominator.
-- Future entries: drive Aggregate_Site_Practitioner_Current (Days Until Next Free).
--   Dr Beth 2026-05-26 (4 days from today): first free slot practice-wide.
--   Dr Alex 2026-06-02 (11 days): Alex's nearest free.
--   Additional entries for the future recall appointment dates.
--
-- Chair Utilisation (Nov 2025, approx):
--   Dr Alex: 180 min booked / 1440 min available (3 days) = 12.5%
--   Dr Beth: 240 min booked / 1920 min available (4 days) = 12.5%
--   (Low because test data has only a handful of appointments — expected.)
-- =============================================================================

DELETE FROM Bronze.Practitioner_Diary WHERE Tenant_ID = 15;
INSERT INTO Bronze.Practitioner_Diary
    (ID, Day, Start_Time, End_Time, Unavailable, Practitioner_ID, Tenant_ID, DW_Loaded_At)
VALUES
    -- Dr Alex NHS (15001) — past: matches appointment dates
    ('T15-PD-001', '2025-11-03', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-002', '2025-11-10', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-003', '2025-11-17', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-004', '2026-01-15', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Dr Alex — future (Days Until Next Free + recall appointment date)
    ('T15-PD-005', '2026-06-02', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-006', '2026-06-15', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Dr Beth Private (15002) — past: matches appointment dates
    ('T15-PD-007', '2025-11-05', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-008', '2025-11-12', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-009', '2025-12-03', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-010', '2025-12-10', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-011', '2026-02-10', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Dr Beth — future (earliest free slot practice-wide + recall appointment date)
    ('T15-PD-012', '2026-05-26', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-013', '2026-06-22', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 22. ADDITIONAL APPOINTMENTS  (future recall bookings + short-notice cancellation)
--
-- 15011, 15012: recall booking future appointments; Pending_At = date booked
--   (= the completed appointment's Start date) so BBYL flag fires for patients
--   15001 and 15004 in Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily.
--   Patients 15001 and 15004 also have these in Gold.Fact_Recalls as Is_Booked=1.
--
-- 15013: short-notice cancellation (cancelled <10 min before start).
--   Cancellation_Reason_ID=2 ('Short Notice Cancellation') triggers Is_Short_Notice=1
--   in Gold.Dim_Cancellation_Reasons.
--   Short Notice Cancellation Rate = 1/2 = 50% (15013 short / 15004+15013 both cancelled)
-- =============================================================================

DELETE FROM Bronze.Appointments WHERE Tenant_ID = 15 AND ID IN (15011, 15012, 15013);
INSERT INTO Bronze.Appointments
    (ID, Patient_ID, Practitioner_ID, User_ID,
     Room_ID,
     Start_Time, Finish_Time, Duration, State,
     Reason, Payment_Plan_ID,
     Pending_At,
     Completed_At, Cancelled_At, Did_Not_Attend_At,
     Appointment_Cancellation_Reason_ID,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- BBYL future recall bookings; Pending_At matches the date they were booked
    (15011, 15001, 15001, 15001, '1500', '2026-06-15T09:00:00Z', '2026-06-15T09:30:00Z', 30, 'waiting',   'Recall Exam',   1500, '2025-11-03T09:30:00Z', NULL, NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15012, 15004, 15002, 15002, '1500', '2026-06-22T10:00:00Z', '2026-06-22T11:00:00Z', 60, 'waiting',   'Recall Review', 1501, '2025-11-05T10:30:00Z', NULL, NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Short-notice cancellation (cancelled 5 min before start on 2026-03-10)
    (15013, 15002, 15001, 15001, '1500', '2026-03-10T10:00:00Z', '2026-03-10T10:30:00Z', 30, 'cancelled', 'Check-up',      1500, NULL,                   NULL, '2026-03-10T09:55:00Z', NULL, 2, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 23. CANCELLATION REASONS  (2 reasons for T15)
--
-- Is_Short_Notice is derived in Gold.usp_Load_Dim_Cancellation_Reasons:
--   LOWER(Reason) LIKE '%short%notice%' → Is_Short_Notice = 1 for reason ID 2.
-- =============================================================================

DELETE FROM Bronze.Cancellation_Reasons WHERE Tenant_ID = 15;
INSERT INTO Bronze.Cancellation_Reasons
    (ID, Active, Reason, Reason_Type, Created_At, Updated_At, Tenant_ID, DW_Loaded_At)
VALUES
    ('1', 1, 'Standard Cancellation',    'patient', '2020-01-01T00:00:00Z', '2020-01-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('2', 1, 'Short Notice Cancellation','patient', '2020-01-01T00:00:00Z', '2020-01-01T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 24. ADDITIONAL APPOINTMENTS  (new working days spread across both FYs)
--
-- 6 working days, 3-4 appointments each = 21 new appointments (IDs 15014-15034).
-- Days chosen to give coverage in months not previously represented:
--   FY 2025-26: 2025-09-15, 2025-10-13, 2026-01-20, 2026-02-17, 2026-03-09
--   FY 2026-27: 2026-04-07
--
-- Appointment types:
--   ~70% exams (30 min) to push Exam Ratio toward 60% target
--   ~30% treatment (45-60 min)
--   1 DNA (15031) across all new appts → DNA rate ~1/21 = 5% (close to 3% target)
--   15013 already provides 1 short-notice cancellation
--
-- New patient first appointments:
--   15006 (Olivia Harris): 2025-09-15 with Dr Alex
--   15007 (Tom Clarke):    2026-01-20 with Dr Beth
--   15008 (Priya Patel):   2026-04-07 with Dr Alex
-- =============================================================================

INSERT INTO Bronze.Appointments
    (ID, Patient_ID, Practitioner_ID, User_ID,
     Room_ID,
     Start_Time, Finish_Time, Duration, State,
     Reason, Payment_Plan_ID,
     Pending_At,
     Completed_At, Cancelled_At, Did_Not_Attend_At,
     Appointment_Cancellation_Reason_ID,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- 2025-09-15 (Dr Alex: 3 appts including new patient Olivia Harris)
    (15014, 15001, 15001, 15001, '1500', '2025-09-15T09:00:00Z', '2025-09-15T09:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2025-09-15T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15015, 15006, 15001, 15001, '1500', '2025-09-15T10:00:00Z', '2025-09-15T10:30:00Z', 30, 'complete', 'New Patient Exam',1501, NULL,                  '2025-09-15T10:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15016, 15003, 15001, 15001, '1500', '2025-09-15T11:00:00Z', '2025-09-15T11:45:00Z', 45, 'complete', 'Filling',       1501, NULL,                   '2025-09-15T11:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- 2025-10-13 (Dr Alex: 3, Dr Beth: 3)
    (15017, 15002, 15001, 15001, '1500', '2025-10-13T09:00:00Z', '2025-10-13T09:30:00Z', 30, 'complete', 'Examination',   1500, NULL,                   '2025-10-13T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15018, 15001, 15001, 15001, '1500', '2025-10-13T10:00:00Z', '2025-10-13T10:45:00Z', 45, 'complete', 'Scale & Polish', 1501, NULL,                  '2025-10-13T10:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15019, 15006, 15001, 15001, '1500', '2025-10-13T11:00:00Z', '2025-10-13T11:30:00Z', 30, 'complete', 'Examination',   1501, '2025-09-15T10:30:00Z', '2025-10-13T11:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),  -- BBYL: booked at 15015
    (15020, 15004, 15002, 15002, '1500', '2025-10-13T09:00:00Z', '2025-10-13T09:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2025-10-13T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15021, 15005, 15002, 15002, '1500', '2025-10-13T10:00:00Z', '2025-10-13T10:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2025-10-13T10:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15022, 15006, 15002, 15002, '1500', '2025-10-13T11:00:00Z', '2025-10-13T11:45:00Z', 45, 'complete', 'Hygiene',       1501, NULL,                   '2025-10-13T11:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- 2026-01-20 (Dr Alex: 3, Dr Beth: 3 including new patient Tom Clarke)
    (15023, 15002, 15001, 15001, '1500', '2026-01-20T09:00:00Z', '2026-01-20T09:30:00Z', 30, 'complete', 'Examination',   1500, NULL,                   '2026-01-20T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15024, 15001, 15001, 15001, '1500', '2026-01-20T10:00:00Z', '2026-01-20T10:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-01-20T10:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15025, 15003, 15001, 15001, '1500', '2026-01-20T11:00:00Z', '2026-01-20T11:45:00Z', 45, 'complete', 'Crown Prep',    1501, NULL,                   '2026-01-20T11:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15026, 15007, 15002, 15002, '1500', '2026-01-20T09:00:00Z', '2026-01-20T09:30:00Z', 30, 'complete', 'New Patient Exam',1501, NULL,                 '2026-01-20T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15027, 15004, 15002, 15002, '1500', '2026-01-20T10:00:00Z', '2026-01-20T10:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-01-20T10:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15028, 15005, 15002, 15002, '1500', '2026-01-20T11:00:00Z', '2026-01-20T11:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-01-20T11:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- 2026-02-17 (Dr Alex: 3, Dr Beth: 2)
    (15029, 15006, 15001, 15001, '1500', '2026-02-17T09:00:00Z', '2026-02-17T09:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-02-17T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15030, 15002, 15001, 15001, '1500', '2026-02-17T10:00:00Z', '2026-02-17T10:45:00Z', 45, 'complete', 'Scale & Polish', 1500, NULL,                  '2026-02-17T10:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15031, 15003, 15001, 15001, '1500', '2026-02-17T11:00:00Z', '2026-02-17T11:30:00Z', 30, 'did_not_attend', 'Review', 1501, NULL,                    NULL,  NULL, '2026-02-17T11:00:00Z', NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15032, 15007, 15002, 15002, '1500', '2026-02-17T09:00:00Z', '2026-02-17T09:30:00Z', 30, 'complete', 'Examination',   1501, '2026-01-20T09:30:00Z', '2026-02-17T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),  -- BBYL: booked at 15026
    (15033, 15004, 15002, 15002, '1500', '2026-02-17T10:00:00Z', '2026-02-17T10:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-02-17T10:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- 2026-03-09 (Dr Alex: 2, Dr Beth: 2)
    (15034, 15001, 15001, 15001, '1500', '2026-03-09T09:00:00Z', '2026-03-09T09:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-03-09T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15035, 15006, 15001, 15001, '1500', '2026-03-09T10:00:00Z', '2026-03-09T10:45:00Z', 45, 'complete', 'Scale & Polish', 1501, NULL,                  '2026-03-09T10:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15036, 15007, 15002, 15002, '1500', '2026-03-09T09:00:00Z', '2026-03-09T09:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-03-09T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15037, 15005, 15002, 15002, '1500', '2026-03-09T10:00:00Z', '2026-03-09T10:45:00Z', 45, 'complete', 'Crown Fit',     1501, NULL,                   '2026-03-09T10:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- 2026-04-07 FY 2026-27 (Dr Alex: 3 including new patient Priya Patel, Dr Beth: 2)
    (15038, 15008, 15001, 15001, '1500', '2026-04-07T09:00:00Z', '2026-04-07T09:30:00Z', 30, 'complete', 'New Patient Exam',1501, NULL,                 '2026-04-07T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15039, 15001, 15001, 15001, '1500', '2026-04-07T10:00:00Z', '2026-04-07T10:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-04-07T10:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15040, 15006, 15001, 15001, '1500', '2026-04-07T11:00:00Z', '2026-04-07T11:45:00Z', 45, 'complete', 'Scale & Polish', 1501, NULL,                  '2026-04-07T11:45:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15041, 15004, 15002, 15002, '1500', '2026-04-07T09:00:00Z', '2026-04-07T09:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-04-07T09:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15042, 15007, 15002, 15002, '1500', '2026-04-07T10:00:00Z', '2026-04-07T10:30:00Z', 30, 'complete', 'Examination',   1501, NULL,                   '2026-04-07T10:30:00Z', NULL, NULL, NULL, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 25. ADDITIONAL DIARY ENTRIES  (one entry per practitioner per new day)
-- =============================================================================

INSERT INTO Bronze.Practitioner_Diary
    (ID, Day, Start_Time, End_Time, Unavailable, Practitioner_ID, Tenant_ID, DW_Loaded_At)
VALUES
    ('T15-PD-014', '2025-09-15', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-015', '2025-10-13', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-016', '2025-10-13', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-017', '2026-01-20', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-018', '2026-01-20', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-019', '2026-02-17', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-020', '2026-02-17', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-021', '2026-03-09', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-022', '2026-03-09', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-023', '2026-04-07', '09:00:00', '17:00:00', 0, 15001, 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('T15-PD-024', '2026-04-07', '09:00:00', '17:00:00', 0, 15002, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 26. ADDITIONAL TREATMENT PLANS  (one per new patient; existing patients reuse
--     their open treatment plans for the new treatment appointments)
-- =============================================================================

INSERT INTO Bronze.Treatment_Plans
    (ID, Patient_ID, Practitioner_ID, Completed,
     Start_Date, End_Date, Completed_At,
     NHS_UDA_Value, NHS_Completed_UDA_Value, Private_Treatment_Value,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- Olivia Harris (private, Dr Alex) — open plan covering Sep 2025 onwards
    (15010, 15006, 15001, 0, '2025-09-15', NULL, NULL, 0, 0, 600, '2025-09-15T09:00:00Z', '2025-09-15T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Tom Clarke (private, Dr Beth) — open plan covering Jan 2026 onwards
    (15011, 15007, 15002, 0, '2026-01-20', NULL, NULL, 0, 0, 400, '2026-01-20T09:00:00Z', '2026-01-20T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- Priya Patel (private, Dr Alex) — open plan starting Apr 2026
    (15012, 15008, 15001, 0, '2026-04-07', NULL, NULL, 0, 0, 350, '2026-04-07T09:00:00Z', '2026-04-07T09:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 27. ADDITIONAL TREATMENT PLAN ITEMS  (exam items for new plans)
-- =============================================================================

INSERT INTO Bronze.Treatment_Plan_Items
    (ID, Treatment_Plan_ID, Patient_ID, Practitioner_ID,
     Nomenclature, NHS_Treatment_Cat, UDA_Band,
     Completed, Completed_At, Charged,
     Price, Appear_On_Invoice,
     Payment_Plan_ID,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('150015', '15010', 15006, 15001, 'Examination',    NULL, NULL, 1, '2025-09-15T10:30:00Z', 1,  85.00, 1, 1501, '2025-09-15T09:00:00Z', '2025-09-15T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150016', '15010', 15006, 15001, 'Scale & Polish', NULL, NULL, 1, '2025-10-13T11:45:00Z', 1,  70.00, 1, 1501, '2025-09-15T09:00:00Z', '2025-10-13T11:45:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150017', '15011', 15007, 15002, 'Examination',    NULL, NULL, 1, '2026-01-20T09:30:00Z', 1,  85.00, 1, 1501, '2026-01-20T09:00:00Z', '2026-01-20T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150018', '15011', 15007, 15002, 'Examination',    NULL, NULL, 1, '2026-02-17T09:30:00Z', 1,  85.00, 1, 1501, '2026-01-20T09:00:00Z', '2026-02-17T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('150019', '15012', 15008, 15001, 'Examination',    NULL, NULL, 1, '2026-04-07T09:30:00Z', 1,  85.00, 1, 1501, '2026-04-07T09:00:00Z', '2026-04-07T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 28. ADDITIONAL TREATMENT APPOINTMENTS  (linking new completed appts to plans)
-- =============================================================================

INSERT INTO Bronze.Treatment_Appointments
    (ID, Appointment_ID, Patient_ID, Treatment_Plan_ID,
     Completed, Completed_At,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- 2025-09-15
    ('1500007', 15014, 15001, 15003, 1, '2025-09-15T09:30:00Z', '2025-09-15T09:00:00Z', '2025-09-15T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- James Smith, TP 15003
    ('1500008', 15015, 15006, 15010, 1, '2025-09-15T10:30:00Z', '2025-09-15T10:00:00Z', '2025-09-15T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Olivia Harris, new TP 15010
    ('1500009', 15016, 15003, 15004, 1, '2025-09-15T11:45:00Z', '2025-09-15T11:00:00Z', '2025-09-15T11:45:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Michael Brown, TP 15004
    -- 2025-10-13
    ('1500010', 15017, 15002, 15002, 1, '2025-10-13T09:30:00Z', '2025-10-13T09:00:00Z', '2025-10-13T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Sarah Jones, TP 15002
    ('1500011', 15018, 15001, 15003, 1, '2025-10-13T10:45:00Z', '2025-10-13T10:00:00Z', '2025-10-13T10:45:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- James Smith, TP 15003
    ('1500012', 15019, 15006, 15010, 1, '2025-10-13T11:30:00Z', '2025-10-13T11:00:00Z', '2025-10-13T11:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Olivia Harris, TP 15010
    ('1500013', 15020, 15004, 15007, 1, '2025-10-13T09:30:00Z', '2025-10-13T09:00:00Z', '2025-10-13T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Emma Wilson, TP 15007
    ('1500014', 15021, 15005, 15008, 1, '2025-10-13T10:30:00Z', '2025-10-13T10:00:00Z', '2025-10-13T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- David Taylor, TP 15008
    -- 2026-01-20
    ('1500015', 15023, 15002, 15002, 1, '2026-01-20T09:30:00Z', '2026-01-20T09:00:00Z', '2026-01-20T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Sarah Jones, TP 15002
    ('1500016', 15024, 15001, 15003, 1, '2026-01-20T10:30:00Z', '2026-01-20T10:00:00Z', '2026-01-20T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- James Smith, TP 15003
    ('1500017', 15026, 15007, 15011, 1, '2026-01-20T09:30:00Z', '2026-01-20T09:00:00Z', '2026-01-20T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Tom Clarke, TP 15011
    ('1500018', 15027, 15004, 15007, 1, '2026-01-20T10:30:00Z', '2026-01-20T10:00:00Z', '2026-01-20T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Emma Wilson, TP 15007
    -- 2026-02-17
    ('1500019', 15029, 15006, 15010, 1, '2026-02-17T09:30:00Z', '2026-02-17T09:00:00Z', '2026-02-17T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Olivia Harris, TP 15010
    ('1500020', 15032, 15007, 15011, 1, '2026-02-17T09:30:00Z', '2026-02-17T09:00:00Z', '2026-02-17T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Tom Clarke, TP 15011
    ('1500021', 15033, 15004, 15007, 1, '2026-02-17T10:30:00Z', '2026-02-17T10:00:00Z', '2026-02-17T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Emma Wilson, TP 15007
    -- 2026-03-09
    ('1500022', 15034, 15001, 15003, 1, '2026-03-09T09:30:00Z', '2026-03-09T09:00:00Z', '2026-03-09T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- James Smith, TP 15003
    ('1500023', 15035, 15006, 15010, 1, '2026-03-09T10:45:00Z', '2026-03-09T10:00:00Z', '2026-03-09T10:45:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Olivia Harris, TP 15010
    ('1500024', 15036, 15007, 15011, 1, '2026-03-09T09:30:00Z', '2026-03-09T09:00:00Z', '2026-03-09T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Tom Clarke, TP 15011
    -- 2026-04-07
    ('1500025', 15038, 15008, 15012, 1, '2026-04-07T09:30:00Z', '2026-04-07T09:00:00Z', '2026-04-07T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Priya Patel, TP 15012
    ('1500026', 15039, 15001, 15003, 1, '2026-04-07T10:30:00Z', '2026-04-07T10:00:00Z', '2026-04-07T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- James Smith, TP 15003
    ('1500027', 15041, 15004, 15007, 1, '2026-04-07T09:30:00Z', '2026-04-07T09:00:00Z', '2026-04-07T09:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),  -- Emma Wilson, TP 15007
    ('1500028', 15042, 15007, 15011, 1, '2026-04-07T10:30:00Z', '2026-04-07T10:00:00Z', '2026-04-07T10:30:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));  -- Tom Clarke, TP 15011
GO

-- =============================================================================
-- 29. ADDITIONAL INVOICES + ITEMS  (for new completed appointments)
--
-- Revenue targets:  FY 2025-26 £20K | FY 2026-27 (YTD to Apr) £3K
-- Existing revenue: FY 2025-26 ~£5K | FY 2026-27 ~£0
-- New revenue:      FY 2025-26 +£3,760 | FY 2026-27 +£520
-- Total FY 2025-26: ~£8,760 (closer to target direction but still below £20K —
--   would need far more appointments to hit £20K; data volume kept modest)
-- =============================================================================

INSERT INTO Bronze.Invoices
    (ID, Patient_ID, Site_ID, User_ID,
     Amount, Paid, Amount_Outstanding,
     Dated_On, Due_On, Reference, Paid_On,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    -- FY 2025-26 new invoices (all fully paid same day)
    (15008, 15006, '1500', 15001,  155.00,  155.00,   0.00, '2025-09-15', '2025-09-15', 'T15-0008', '2025-09-15', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15009, 15001, '1500', 15001,   95.00,   95.00,   0.00, '2025-09-15', '2025-09-15', 'T15-0009', '2025-09-15', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15010, 15003, '1500', 15001,  320.00,  320.00,   0.00, '2025-09-15', '2025-09-15', 'T15-0010', '2025-09-15', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15011, 15002, '1500', 15001,   65.20,   65.20,   0.00, '2025-10-13', '2025-10-13', 'T15-0011', '2025-10-13', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15012, 15001, '1500', 15001,  110.00,  110.00,   0.00, '2025-10-13', '2025-10-13', 'T15-0012', '2025-10-13', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15013, 15006, '1500', 15001,   70.00,   70.00,   0.00, '2025-10-13', '2025-10-13', 'T15-0013', '2025-10-13', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15014, 15004, '1500', 15002,   95.00,   95.00,   0.00, '2025-10-13', '2025-10-13', 'T15-0014', '2025-10-13', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15015, 15005, '1500', 15002,   95.00,   95.00,   0.00, '2025-10-13', '2025-10-13', 'T15-0015', '2025-10-13', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15016, 15006, '1500', 15002,   95.00,   95.00,   0.00, '2025-10-13', '2025-10-13', 'T15-0016', '2025-10-13', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15017, 15002, '1500', 15001,   65.20,   65.20,   0.00, '2026-01-20', '2026-01-20', 'T15-0017', '2026-01-20', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15018, 15001, '1500', 15001,   95.00,   95.00,   0.00, '2026-01-20', '2026-01-20', 'T15-0018', '2026-01-20', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15019, 15007, '1500', 15002,   85.00,   85.00,   0.00, '2026-01-20', '2026-01-20', 'T15-0019', '2026-01-20', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15020, 15004, '1500', 15002,   95.00,   95.00,   0.00, '2026-01-20', '2026-01-20', 'T15-0020', '2026-01-20', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15021, 15006, '1500', 15001,   95.00,   95.00,   0.00, '2026-02-17', '2026-02-17', 'T15-0021', '2026-02-17', '2026-02-17T00:00:00Z', '2026-02-17T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15022, 15007, '1500', 15002,   85.00,   85.00,   0.00, '2026-02-17', '2026-02-17', 'T15-0022', '2026-02-17', '2026-02-17T00:00:00Z', '2026-02-17T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15023, 15004, '1500', 15002,   95.00,   95.00,   0.00, '2026-02-17', '2026-02-17', 'T15-0023', '2026-02-17', '2026-02-17T00:00:00Z', '2026-02-17T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15024, 15001, '1500', 15001,   95.00,   95.00,   0.00, '2026-03-09', '2026-03-09', 'T15-0024', '2026-03-09', '2026-03-09T00:00:00Z', '2026-03-09T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15025, 15006, '1500', 15001,  110.00,  110.00,   0.00, '2026-03-09', '2026-03-09', 'T15-0025', '2026-03-09', '2026-03-09T00:00:00Z', '2026-03-09T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15026, 15007, '1500', 15002,   85.00,   85.00,   0.00, '2026-03-09', '2026-03-09', 'T15-0026', '2026-03-09', '2026-03-09T00:00:00Z', '2026-03-09T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- FY 2026-27 invoices (Apr 2026 only)
    (15027, 15008, '1500', 15001,   85.00,   85.00,   0.00, '2026-04-07', '2026-04-07', 'T15-0027', '2026-04-07', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15028, 15001, '1500', 15001,   95.00,   95.00,   0.00, '2026-04-07', '2026-04-07', 'T15-0028', '2026-04-07', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15029, 15004, '1500', 15002,   95.00,   95.00,   0.00, '2026-04-07', '2026-04-07', 'T15-0029', '2026-04-07', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15030, 15007, '1500', 15002,   85.00,   85.00,   0.00, '2026-04-07', '2026-04-07', 'T15-0030', '2026-04-07', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

INSERT INTO Bronze.Invoice_Items
    (ID, Invoice_ID, Practitioner_ID, User_ID,
     Name, Item_Price, Quantity, Total_Price, NHS_Charge,
     Treatment_Plan_ID, Treatment_Plan_Item_ID,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    ('1500011', 15008, 15001, 15001, 'New Patient Examination',  85.00, 1,  85.00, 0, 15010, '150015', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500012', 15008, 15001, 15001, 'X-Ray',                    70.00, 1,  70.00, 0, 15010, '150015', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500013', 15009, 15001, 15001, 'Examination',              95.00, 1,  95.00, 0, 15003, '150005', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500014', 15010, 15001, 15001, 'Composite Filling',       320.00, 1, 320.00, 0, 15004, '150007', '2025-09-15T00:00:00Z', '2025-09-15T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500015', 15011, 15001, 15001, 'NHS Band 1 Examination',   65.20, 1,  65.20, 1, 15002, '150004', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500016', 15012, 15001, 15001, 'Scale & Polish',          110.00, 1, 110.00, 0, 15003, '150005', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500017', 15013, 15001, 15001, 'Examination',              70.00, 1,  70.00, 0, 15010, '150015', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500018', 15014, 15002, 15002, 'Examination',              95.00, 1,  95.00, 0, 15007, '150010', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500019', 15015, 15002, 15002, 'Examination',              95.00, 1,  95.00, 0, 15008, '150011', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500020', 15016, 15002, 15002, 'Hygiene Session',          95.00, 1,  95.00, 0, 15010, '150016', '2025-10-13T00:00:00Z', '2025-10-13T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500021', 15017, 15001, 15001, 'NHS Band 1 Examination',   65.20, 1,  65.20, 1, 15002, '150003', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500022', 15018, 15001, 15001, 'Examination',              95.00, 1,  95.00, 0, 15003, '150005', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500023', 15019, 15002, 15002, 'New Patient Examination',  85.00, 1,  85.00, 0, 15011, '150017', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500024', 15020, 15002, 15002, 'Examination',              95.00, 1,  95.00, 0, 15007, '150010', '2026-01-20T00:00:00Z', '2026-01-20T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500025', 15021, 15001, 15001, 'Examination',              95.00, 1,  95.00, 0, 15010, '150015', '2026-02-17T00:00:00Z', '2026-02-17T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500026', 15022, 15002, 15002, 'Examination',              85.00, 1,  85.00, 0, 15011, '150018', '2026-02-17T00:00:00Z', '2026-02-17T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500027', 15023, 15002, 15002, 'Examination',              95.00, 1,  95.00, 0, 15007, '150010', '2026-02-17T00:00:00Z', '2026-02-17T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500028', 15024, 15001, 15001, 'Examination',              95.00, 1,  95.00, 0, 15003, '150005', '2026-03-09T00:00:00Z', '2026-03-09T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500029', 15025, 15001, 15001, 'Scale & Polish',          110.00, 1, 110.00, 0, 15010, '150016', '2026-03-09T00:00:00Z', '2026-03-09T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500030', 15026, 15002, 15002, 'Examination',              85.00, 1,  85.00, 0, 15011, '150017', '2026-03-09T00:00:00Z', '2026-03-09T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    -- FY 2026-27
    ('1500031', 15027, 15001, 15001, 'New Patient Examination',  85.00, 1,  85.00, 0, 15012, '150019', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500032', 15028, 15001, 15001, 'Examination',              95.00, 1,  95.00, 0, 15003, '150005', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500033', 15029, 15002, 15002, 'Examination',              95.00, 1,  95.00, 0, 15007, '150010', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    ('1500034', 15030, 15002, 15002, 'Examination',              85.00, 1,  85.00, 0, 15011, '150017', '2026-04-07T00:00:00Z', '2026-04-07T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 30. ADDITIONAL PAYMENTS  (one per new invoice, all fully paid)
-- =============================================================================

INSERT INTO Bronze.Payments
    (Payment_ID, Patient_ID, Site_ID, User_ID, Practitioner_ID,
     Amount, Amount_Unexplained, Method, Dated_On, Status, Deleted,
     Explanation_Amount, Explanation_Invoice_ID,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15008, 15006, '1500', 15001, 15001,  155.00, 0, 'card',        '2025-09-15', 'complete', 0,  155.00, 15008, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15009, 15001, '1500', 15001, 15001,   95.00, 0, 'card',        '2025-09-15', 'complete', 0,   95.00, 15009, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15010, 15003, '1500', 15001, 15001,  320.00, 0, 'card',        '2025-09-15', 'complete', 0,  320.00, 15010, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15011, 15002, '1500', 15001, 15001,   65.20, 0, 'cash',        '2025-10-13', 'complete', 0,   65.20, 15011, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15012, 15001, '1500', 15001, 15001,  110.00, 0, 'card',        '2025-10-13', 'complete', 0,  110.00, 15012, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15013, 15006, '1500', 15001, 15001,   70.00, 0, 'card',        '2025-10-13', 'complete', 0,   70.00, 15013, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15014, 15004, '1500', 15002, 15002,   95.00, 0, 'card',        '2025-10-13', 'complete', 0,   95.00, 15014, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15015, 15005, '1500', 15002, 15002,   95.00, 0, 'card',        '2025-10-13', 'complete', 0,   95.00, 15015, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15016, 15006, '1500', 15002, 15002,   95.00, 0, 'card',        '2025-10-13', 'complete', 0,   95.00, 15016, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15017, 15002, '1500', 15001, 15001,   65.20, 0, 'cash',        '2026-01-20', 'complete', 0,   65.20, 15017, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15018, 15001, '1500', 15001, 15001,   95.00, 0, 'card',        '2026-01-20', 'complete', 0,   95.00, 15018, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15019, 15007, '1500', 15002, 15002,   85.00, 0, 'card',        '2026-01-20', 'complete', 0,   85.00, 15019, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15020, 15004, '1500', 15002, 15002,   95.00, 0, 'card',        '2026-01-20', 'complete', 0,   95.00, 15020, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15021, 15006, '1500', 15001, 15001,   95.00, 0, 'card',        '2026-02-17', 'complete', 0,   95.00, 15021, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15022, 15007, '1500', 15002, 15002,   85.00, 0, 'card',        '2026-02-17', 'complete', 0,   85.00, 15022, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15023, 15004, '1500', 15002, 15002,   95.00, 0, 'card',        '2026-02-17', 'complete', 0,   95.00, 15023, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15024, 15001, '1500', 15001, 15001,   95.00, 0, 'card',        '2026-03-09', 'complete', 0,   95.00, 15024, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15025, 15006, '1500', 15001, 15001,  110.00, 0, 'card',        '2026-03-09', 'complete', 0,  110.00, 15025, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15026, 15007, '1500', 15002, 15002,   85.00, 0, 'card',        '2026-03-09', 'complete', 0,   85.00, 15026, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15027, 15008, '1500', 15001, 15001,   85.00, 0, 'card',        '2026-04-07', 'complete', 0,   85.00, 15027, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15028, 15001, '1500', 15001, 15001,   95.00, 0, 'card',        '2026-04-07', 'complete', 0,   95.00, 15028, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15029, 15004, '1500', 15002, 15002,   95.00, 0, 'card',        '2026-04-07', 'complete', 0,   95.00, 15029, 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15030, 15007, '1500', 15002, 15002,   85.00, 0, 'card',        '2026-04-07', 'complete', 0,   85.00, 15030, 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

-- =============================================================================
-- 31. ADDITIONAL PATIENT STATS  (new patients 15006-15008)
-- =============================================================================

INSERT INTO Bronze.Patient_Stats
    (Patient_ID, First_Appointment_Date, First_Exam_Date,
     Last_Appointment_Date, Last_Exam_Date, Last_Scale_And_Polish_Date,
     Next_Appointment_Date, Next_Exam_Date, Next_Scale_And_Polish_Date,
     Last_FTA_Appointment_Date, Last_Cancelled_Appointment_Date,
     Total_Paid, Total_Invoiced,
     NHS_Exemption_Code,
     Created_At, Updated_At,
     Tenant_ID, DW_Loaded_At)
VALUES
    (15006, '2025-09-15', '2025-09-15', '2026-04-07', '2026-04-07', '2026-03-09', NULL, NULL, NULL, NULL, NULL,  525.00,  525.00, NULL, '2025-09-15T00:00:00Z', '2026-05-29T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15007, '2026-01-20', '2026-01-20', '2026-04-07', '2026-04-07', NULL,          NULL, NULL, NULL, NULL, NULL,  340.00,  340.00, NULL, '2026-01-20T00:00:00Z', '2026-05-29T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3))),
    (15008, '2026-04-07', '2026-04-07', '2026-04-07', '2026-04-07', NULL,          NULL, NULL, NULL, NULL, NULL,   85.00,   85.00, NULL, '2026-04-07T00:00:00Z', '2026-05-29T00:00:00Z', 15, CAST(GETUTCDATE() AS datetime2(3)));
GO

PRINT 'T15 Bronze seed complete. Run Silver.usp_Load_All then Gold pipeline SPs to propagate data.';
GO
