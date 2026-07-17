-- Billing.Profile_Pricing seed -- base prices effective from 2026-07 (YYYYMM 202607).
-- To change a price later, just INSERT a newer (Profile_Key, Year_Month) row, e.g.:
--   INSERT INTO Billing.Profile_Pricing VALUES ('front_office', 202701, 6.00);  -- FO -> GBP6 from Jan 2027
-- The rollup for a billed month picks the latest row with Year_Month <= that month.
DELETE FROM [Billing].[Profile_Pricing];
INSERT INTO [Billing].[Profile_Pricing] ([Profile_Key],[Year_Month],[Monthly_Price]) VALUES
 ('full',         202607, 50.00),
 ('clinician',    202607, 20.00),
 ('front_office', 202607,  5.00);
GO
