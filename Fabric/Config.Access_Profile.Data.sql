-- Config.Access_Profile seed (vendor-managed profiles + prices). "for now" prices:
--   Full         (all modules + Maintain_Targets)             GBP 50  -- practice owners / managers
--   Clinician    (own data: Home/Clinical/NHS/Schedule/       GBP 20  -- forced to their own practitioner
--                 Patient/My Data)
--   Front Office (Home/Schedule/Patient)                      GBP 5
--   No Access    (subscribed off -- nothing billed)           GBP 0
DELETE FROM [Config].[Access_Profile];
INSERT INTO [Config].[Access_Profile] ([Profile_Key],[Display_Name],[Monthly_Price],[Display_Order]) VALUES
 ('full',         'Full',         50.00, 1),
 ('clinician',    'Clinician',    20.00, 2),
 ('front_office', 'Front Office',  5.00, 3),
 ('no_access',    'No Access',     0.00, 4);
GO
