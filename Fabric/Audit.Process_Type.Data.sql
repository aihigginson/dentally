-- =============================================================================
-- Audit.Process_Type — seed data
-- =============================================================================

DELETE FROM Audit.Process_Type;
GO

INSERT INTO Audit.Process_Type (Process_Type_Code, Process_Type_Desc) VALUES ('PROCEDURE', 'SQL Stored Procedure');
INSERT INTO Audit.Process_Type (Process_Type_Code, Process_Type_Desc) VALUES ('NOTEBOOK',  'Microsoft Fabric Notebook');
GO
