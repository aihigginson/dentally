--------------------------------------------------------------------
--  Table            :  Audit.Xero_Watermark
--  Author           :  AIH
--  Initial Date     :  2026-08-03
--  Notes            :  Per-tenant incremental high-watermark for the Xero ingest. Ingest_Xero
--                      reads Modified_Since, pulls Xero line endpoints (Invoices / CreditNotes /
--                      BankTransactions / ManualJournals) with an If-Modified-Since header
--                      (Modified_Since minus an overlap), then advances it to the run start.
--                      A missing row = COLD -> full pull (which self-bootstraps the watermark).
--                      Keeps Xero under its 60/min + 5000/day per-tenant rate limits.
--------------------------------------------------------------------
IF OBJECT_ID('Audit.Xero_Watermark') IS NULL
CREATE TABLE Audit.Xero_Watermark
(
      Tenant_ID       INT           NOT NULL
    , Modified_Since  DATETIME2(3)  NOT NULL
    , DW_Updated_At   DATETIME2(3)  NOT NULL
);
GO
