-- V097__drop_defunct_usp_load_all.sql
-- Retire the defunct Silver+Gold orchestrator. Superseded by the Orchestrate_Build notebook
-- (metadata DAG over Audit.Process_Config + Audit.Process_Dependency). No DAG job invokes it.
DROP PROCEDURE IF EXISTS [Audit].[usp_Load_All];
GO
