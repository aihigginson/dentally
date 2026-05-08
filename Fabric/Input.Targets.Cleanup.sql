-- Input.Targets cleanup
-- Removes rows whose Metric key no longer exists in Config.Metric_Definitions.
-- Run after Config.Metric_Definitions.Data.sql so the definition list is current.
DELETE FROM [Input].[Targets]
WHERE [Metric] NOT IN (SELECT [Metric_Key] FROM [Config].[Metric_Definitions]);
GO
