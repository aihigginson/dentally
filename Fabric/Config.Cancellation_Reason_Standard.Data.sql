-- Seed data for Config.Cancellation_Reason_Standard
MERGE [Config].[Cancellation_Reason_Standard] AS tgt
USING (VALUES
    ('Patient - Personal',    1,  1),
    ('Patient - Work',        2,  1),
    ('Patient - Unwell',      3,  1),
    ('Patient - Financial',   4,  1),
    ('Short Notice',          5,  1),
    ('Did Not Attend',        6,  1),
    ('Practice Initiated',    7,  1),
    ('Other',                 99, 1)
) AS src ([Standard_Cancellation_Reason], [Display_Order], [Is_Active])
ON tgt.[Standard_Cancellation_Reason] = src.[Standard_Cancellation_Reason]
WHEN MATCHED THEN UPDATE SET
    [Display_Order] = src.[Display_Order],
    [Is_Active]     = src.[Is_Active]
WHEN NOT MATCHED BY TARGET THEN INSERT
    ([Standard_Cancellation_Reason], [Display_Order], [Is_Active])
    VALUES (src.[Standard_Cancellation_Reason], src.[Display_Order], src.[Is_Active]);
