--------------------------------------------------------------------
--  Table  :  Gold.Invoice_Discount
--  Author :  AIH
--  Purpose:  The "positive only" set of discounted invoices -- the EXCEPTION,
--            not the rule, plus how much was given away.
--
--            TWO SHAPES, because practices record a discount in two different ways
--            and only one of them was ever detected:
--              * AS AN ITEM -- a negative line named 'Discount'. This is what the
--                live practice does (654 lines, -GBP 88,350 since 2021) and it was
--                invisible: the negative is INSIDE the line sum, so the old
--                "header > lines" test was always false. It found 0 of 650.
--              * AS A HEADER GAP -- invoice Amount exceeds the sum of its lines.
--                The demo generator produces this shape, which is why the metric
--                looked exercised when no real discount had ever been counted. Rather than materialise Is_Discount on every
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
        [Tenant_ID]      [int] NOT NULL,
        [Invoice_ID]     [int] NOT NULL,
        [Discount_Value] [decimal](18, 4) NULL
    );
GO

-- Added after the table existed, so an ALTER as well as the CREATE above. "How much did we
-- discount" is the question actually being asked; a flag alone cannot answer it.
IF NOT EXISTS (SELECT 1 FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id
               JOIN sys.schemas s ON s.schema_id = t.schema_id
               WHERE s.name = 'Gold' AND t.name = 'Invoice_Discount' AND c.name = 'Discount_Value')
    ALTER TABLE [Gold].[Invoice_Discount] ADD [Discount_Value] [decimal](18, 4) NULL;
GO
