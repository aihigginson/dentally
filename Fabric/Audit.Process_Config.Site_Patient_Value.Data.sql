-- =============================================================================
-- Audit.Process_Config / Process_Dependency -- V188: retire GOLD_AGG_PATIENT_VALUE
-- =============================================================================
-- Re-runnable: every statement is guarded, because these two tables carry the whole build's
-- orchestration and a release must never duplicate a row into them.
--
-- V187 registered GOLD_AGG_PATIENT_VALUE as its own node. It should never have been one. Its
-- aggregate was one row per patient, carrying a site and a tenant, in category GOLD_AGG, at
-- dependency level 5, driven off the same Dim_Patients spine -- which is a description of
-- GOLD_AGG_SITE_PATIENT, a node that already existed. So the value columns move onto that
-- table and this node goes away.
--
-- GOLD_AGG_SITE_PATIENT now reads two facts it did not before. They go in at level 5 like its
-- existing dependencies: a node's level is MAX of its dependency levels, the facts are level 4,
-- so this leaves the aggregate where it already sat and still guarantees it runs after them.
--
-- ==> FACT_REVENUE IN PARTICULAR MUST COME FIRST. <== That is where the capitation half of a
-- patient's value lives. Reading it early would produce the invoiced-only figure these columns
-- exist to replace -- quietly, and looking entirely plausible.
-- =============================================================================

INSERT INTO [Audit].[Process_Dependency]
    (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
SELECT v.prev, 'GOLD_AGG_SITE_PATIENT', 'DATA', 5, 1
FROM (VALUES ('GOLD_FACT_REVENUE'), ('GOLD_FACT_APPOINTMENTS'), ('GOLD_DIM_DATE')) AS v(prev)
WHERE NOT EXISTS (SELECT 1 FROM [Audit].[Process_Dependency] d
                   WHERE d.Prev_Process_Code = v.prev
                     AND d.Next_Process_Code = 'GOLD_AGG_SITE_PATIENT');
GO

-- Say what the table now holds, so the next person reading the run log knows the value columns
-- are rebuilt here and does not go looking for a separate process that no longer exists.
UPDATE [Audit].[Process_Config]
   SET Process_Desc = 'Rebuild Gold.Aggregate_Site_Patient_Current -- current status per patient per site (retained, active, recall due/sent, future appointment) AND what the patient is worth over a rolling 36 months, invoiced AND capitation, with attendance alongside. The value columns replaced the "Lifetime Value" measure, which summed invoiced value only and so showed membership patients as worth half a private patient when they are worth twice as much. GOLD_AGG: reads Gold.Dim_Patients + Dim_Practice_Sites + Dim_Date + Fact_Recalls + Fact_Revenue + Fact_Appointments.'
 WHERE Process_Code = 'GOLD_AGG_SITE_PATIENT';
GO

-- Dependencies first: Process_Dependency references the code.
DELETE FROM [Audit].[Process_Dependency] WHERE Next_Process_Code = 'GOLD_AGG_PATIENT_VALUE';
GO
DELETE FROM [Audit].[Process_Config]     WHERE Process_Code      = 'GOLD_AGG_PATIENT_VALUE';
GO

DROP TABLE IF EXISTS [Gold].[Aggregate_Patient_Value];
GO
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Patient_Value];
GO
