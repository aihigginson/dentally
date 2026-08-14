-- V142: add Lapsed_Date + Lapsed_Reason to Gold.Dim_Patients WITHOUT dropping the table, so the
-- existing pk_Patient values (and every fact's fk_Patient reference) survive. The load SP backfills
-- both on its next run; a fresh build gets them from the updated Table.sql. Lapsed_Reason is DERIVED
-- from the lapse type -- Dentally's archived_reason is NOT ingested (data-minimised + empty on the
-- real tenant-100 data), so re-including it would add the PII/DPIA cost for zero data.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Patients') AND name = 'Lapsed_Date')
    ALTER TABLE Gold.Dim_Patients ADD Lapsed_Date date NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Patients') AND name = 'Lapsed_Reason')
    ALTER TABLE Gold.Dim_Patients ADD Lapsed_Reason varchar(255) NULL;
GO
