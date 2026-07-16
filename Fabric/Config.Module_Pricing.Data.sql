-- Config.Module_Pricing seed (vendor-managed catalogue + placeholder prices).
-- Prices are PLACEHOLDERS calibrated so the default profile bundles land near the intended tiers
-- (Principal = all 10 ~= GBP 30; Clinical bundle ~= GBP 17; Front Office ~= GBP 6). Adjust to the
-- real per-module GBP once agreed -- with per-module billing the "tier price" is emergent.
DELETE FROM [Config].[Module_Pricing];
INSERT INTO [Config].[Module_Pricing] ([Module_Key],[Display_Name],[Monthly_Price],[Display_Order],[Is_Active]) VALUES
 ('Home',      'Home',       0.00,  1, 1),
 ('Revenue',   'Revenue',    4.00,  2, 1),
 ('Patient',   'Patient',    3.00,  3, 1),
 ('Schedule',  'Schedule',   3.00,  4, 1),
 ('Clinical',  'Clinical',   4.00,  5, 1),
 ('NHS',       'NHS',        3.00,  6, 1),
 ('Day_Book',  'Day Book',   3.00,  7, 1),
 ('Finance',   'Finance',    5.00,  8, 1),
 ('My_Data',   'My Data',    2.00,  9, 1),
 ('Marketing', 'Marketing',  3.00, 10, 1);
GO
