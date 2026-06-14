--------------------------------------------------------------------
--  Table  :  Gold.Payment_Deposit
--  Author :  AIH
--  Purpose:  The "positive only" set of deposit payments -- the rare EXCEPTION.
--            A deposit = money received but not yet earned (Amount_Unexplained +
--            allocations to invoice items for incomplete treatment plans). Rather
--            than materialise Is_Deposit / Deposit_Amount on every payment fact row
--            (and drag the cross-entity deposit dependency into the fact load), we
--            store only the deposit payments + amount here and LEFT JOIN them in
--            Gold.vw_Fact_Payments (absent => not a deposit, amount 0). Rebuilt at
--            the end of the payments load.
--
--            Fully rebuilt each load -> guarded create so a redeploy preserves it.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
               WHERE s.name = 'Gold' AND t.name = 'Payment_Deposit')
    CREATE TABLE [Gold].[Payment_Deposit](
        [Tenant_ID]      [int]            NOT NULL,
        [Payment_ID]     [int]            NOT NULL,
        [Deposit_Amount] [decimal](12,2)  NULL
    );
GO
