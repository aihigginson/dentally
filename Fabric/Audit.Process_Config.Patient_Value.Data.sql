-- =============================================================================
-- Audit.Process_Config / Process_Dependency -- register GOLD_AGG_PATIENT_VALUE
-- =============================================================================
-- Re-runnable: every statement is NOT EXISTS guarded, because these two tables carry the
-- whole build's orchestration and a release must never duplicate a row into them.
--
-- Dependency_Level 5 and DATA dependencies on the facts it reads, matching
-- GOLD_AGG_PATIENT_AT_RISK -- the aggregate closest to it in shape. It must run after
-- Fact_Revenue in particular: that is where the capitation half of a patient's value lives,
-- and reading it early would silently produce the invoiced-only figure this aggregate exists
-- to replace.
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM [Audit].[Process_Config] WHERE Process_Code = 'GOLD_AGG_PATIENT_VALUE')
INSERT INTO [Audit].[Process_Config]
    (Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code, Process_Type_Code)
VALUES
    ('GOLD_AGG_PATIENT_VALUE',
     'Gold.usp_Load_Aggregate_Patient_Value',
     'Rebuild Gold.Aggregate_Patient_Value -- what each patient is worth over a rolling 36 months, invoiced AND capitation, with attendance alongside. Replaces the "Lifetime Value" measure, which summed invoiced value only and so showed membership patients as worth half a private patient when they are worth twice as much. GOLD_AGG: reads Gold.Fact_Revenue + Fact_Appointments + Dim_Patients.',
     '@Mode = ''LIVE'', @Logging = 1',
     'GOLD_AGG', 'PROCEDURE');
GO

INSERT INTO [Audit].[Process_Dependency]
    (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
SELECT v.prev, 'GOLD_AGG_PATIENT_VALUE', 'DATA', 5, 1
FROM (VALUES ('GOLD_FACT_REVENUE'), ('GOLD_FACT_APPOINTMENTS'), ('GOLD_DIM_PATIENTS'),
             ('GOLD_DIM_PRACTICE_SITES'), ('GOLD_DIM_DATE')) AS v(prev)
WHERE NOT EXISTS (SELECT 1 FROM [Audit].[Process_Dependency] d
                   WHERE d.Prev_Process_Code = v.prev
                     AND d.Next_Process_Code = 'GOLD_AGG_PATIENT_VALUE');
GO
