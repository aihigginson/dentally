-- =====================================================================
-- V079 -- Populate Fact_Recall_Gap + expose it to PBI
-- =====================================================================
-- Runs the initial load of the new Retention Outlook worklist fact, then regenerates the
-- PBI presentation views so PBI.[_Recall Gap] is created from the new Gold table (the view
-- generator builds from sys.columns, so the table just needs to exist first).
-- Ongoing builds pick it up via the GOLD_AGG_RECALL_GAP Process_Config row (GOLD_AGG runs
-- after the Gold facts). Re-run Generate_Process_Dependencies if the build uses the static
-- dependency file rather than category ordering.
-- =====================================================================

DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC [Gold].[usp_Load_Fact_Recall_Gap] @Mode = 'PROD', @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
GO

EXEC [Meta].[usp_Create_Gold_Views];
GO
