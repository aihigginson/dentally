--------------------------------------------------------------------
--  Table  :  Gold.Invoice_Discount
--  Author :  AIH
--  Purpose:  The "positive only" set of discounted invoices -- the EXCEPTION,
--            not the rule. A discount = invoice header Amount exceeds the sum of
--            its line Total Price. Rather than materialise Is_Discount on every
--            fact row (a dense flag that is almost always 0, plus a per-invoice
--            window that blocks delta loading), we store only the discounted
--            invoices here and LEFT JOIN them in Gold.vw_Fact_Invoice_Items
--            (absent => not discounted). Rebuilt at the end of the invoice-items
--            load (cheap: a small GROUP BY ... HAVING aggregate).
--
--            Data-bearing-ish but fully rebuilt each load -> guarded create so a
--            redeploy preserves the table; the load repopulates it.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
               WHERE s.name = 'Gold' AND t.name = 'Invoice_Discount')
    CREATE TABLE [Gold].[Invoice_Discount](
        [Tenant_ID]  [int] NOT NULL,
        [Invoice_ID] [int] NOT NULL
    );
GO
