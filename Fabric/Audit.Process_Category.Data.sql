-- =============================================================================
-- Audit.Process_Category — seed data
-- =============================================================================

DELETE FROM Audit.Process_Category;
GO

INSERT INTO Audit.Process_Category (Process_Category_Code, Process_Category_Desc) VALUES ('BRONZE',    'Bronze layer: Stage Delta tables → Bronze Warehouse upserts');
INSERT INTO Audit.Process_Category (Process_Category_Code, Process_Category_Desc) VALUES ('SILVER',    'Silver layer: Bronze → Silver typed and cleaned');
INSERT INTO Audit.Process_Category (Process_Category_Code, Process_Category_Desc) VALUES ('GOLD',      'Gold layer: orchestrators');
INSERT INTO Audit.Process_Category (Process_Category_Code, Process_Category_Desc) VALUES ('GOLD_DIM',  'Gold layer: dimension table loads');
INSERT INTO Audit.Process_Category (Process_Category_Code, Process_Category_Desc) VALUES ('GOLD_FACT', 'Gold layer: fact table loads');
INSERT INTO Audit.Process_Category (Process_Category_Code, Process_Category_Desc) VALUES ('GOLD_AGG',  'Gold layer: aggregate/terminal loads (read Gold facts/dims)');
INSERT INTO Audit.Process_Category (Process_Category_Code, Process_Category_Desc) VALUES ('POSTRUN_GATE', 'Post-run gates: run AFTER the DAG waves (excluded from them), e.g. the referential-integrity check');
GO
