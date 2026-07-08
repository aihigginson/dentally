-- ===========================================================================
-- V052  treatment_plan_course_rollup
-- ---------------------------------------------------------------------------
-- Pushes the treatment-plan-ITEM roll-up up onto Gold.Fact_Treatment_Plans so
-- the plan grain carries the "open course" lifecycle without routing through the
-- line-grain fact. Populated by Gold.usp_Load_Fact_Treatment_Plans:
--   Private_Treatment_Value_Completed    = SUM item Total_Price WHERE Completed, NHS_Charge=0
--   Private_Treatment_Value_Outstanding  = SUM item Total_Price WHERE open,      NHS_Charge=0
--   Last_Activity_Date                   = MAX Completed_At of completed items (pushed up)
--   Has_Completed_Item / Has_Open_Item   = item state flags
--   Has_Future_Appointment               = plan has a non-cancelled appt today-or-later
--   Course_Status                        = Complete / Effectively Complete / Proposed /
--                                          In Progress / Open - No Appointment / No Items
-- STRUCTURAL only -- the 3-month recency band is computed in DAX off Last_Activity_Date
-- (TODAY()-relative) so a course ages into "stale" with NO row rebuild.
-- ALTER in place (not drop/create) so the surrogate keys other objects point at survive.
-- Guarded + forward-only. NB: Fabric Warehouse is VARCHAR-only (no NVARCHAR).
-- ===========================================================================

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Treatment_Plans') AND name = 'Private_Treatment_Value_Completed')
    ALTER TABLE Gold.Fact_Treatment_Plans ADD [Private_Treatment_Value_Completed] DECIMAL(18,4) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Treatment_Plans') AND name = 'Private_Treatment_Value_Outstanding')
    ALTER TABLE Gold.Fact_Treatment_Plans ADD [Private_Treatment_Value_Outstanding] DECIMAL(18,4) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Treatment_Plans') AND name = 'Last_Activity_Date')
    ALTER TABLE Gold.Fact_Treatment_Plans ADD [Last_Activity_Date] DATE NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Treatment_Plans') AND name = 'Has_Completed_Item')
    ALTER TABLE Gold.Fact_Treatment_Plans ADD [Has_Completed_Item] BIT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Treatment_Plans') AND name = 'Has_Open_Item')
    ALTER TABLE Gold.Fact_Treatment_Plans ADD [Has_Open_Item] BIT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Treatment_Plans') AND name = 'Has_Future_Appointment')
    ALTER TABLE Gold.Fact_Treatment_Plans ADD [Has_Future_Appointment] BIT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Treatment_Plans') AND name = 'Course_Status')
    ALTER TABLE Gold.Fact_Treatment_Plans ADD [Course_Status] VARCHAR(40) NULL;
