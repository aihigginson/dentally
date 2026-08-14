-- V145: add Is_Rolled_Forward to Gold.Dim_NHS_Contracts WITHOUT dropping it (persistent MERGE dim, so
-- an ALTER preserves pk_NHS_Contract + every fact's fk). Real source contracts = 0; rows the load
-- synthesises to cover NHS years that have submissions but no contract = 1. The load backfills 0 on
-- existing rows via its hash-gated UPDATE.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_NHS_Contracts') AND name = 'Is_Rolled_Forward')
    ALTER TABLE Gold.Dim_NHS_Contracts ADD Is_Rolled_Forward bit NULL;
GO
