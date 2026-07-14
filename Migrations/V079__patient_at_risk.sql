-- =====================================================================
-- V079 -- Populate Fact_Patient_At_Risk + expose it to PBI
-- =====================================================================
-- Runs the initial load of the At Risk fact (active patients with no relevant future appointment,
-- by retention route), then regenerates the PBI presentation views so PBI.[_Patient At Risk] is
-- created from the new Gold table. Ongoing builds pick it up via the GOLD_AGG_PATIENT_AT_RISK
-- Process_Config row + regenerated dependencies (GOLD_AGG runs after the Gold facts it reads).
-- =====================================================================

DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC [Gold].[usp_Load_Fact_Patient_At_Risk] @Mode = 'PROD', @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
GO

EXEC [Meta].[usp_Create_Gold_Views];
GO
