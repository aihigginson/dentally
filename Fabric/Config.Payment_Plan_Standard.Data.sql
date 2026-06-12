-- Seed data for Config.Payment_Plan_Standard
MERGE [Config].[Payment_Plan_Standard] AS tgt
USING (VALUES
    ('NHS',       1,  1),
    ('Private',   2,  1),
    ('Care Plan', 3,  1),
    ('Insurance', 4,  1),
    ('Other',     99, 1)
) AS src ([Standard_Payment_Plan], [Display_Order], [Is_Active])
ON tgt.[Standard_Payment_Plan] = src.[Standard_Payment_Plan]
WHEN MATCHED THEN UPDATE SET
    [Display_Order] = src.[Display_Order],
    [Is_Active]     = src.[Is_Active]
WHEN NOT MATCHED BY TARGET THEN INSERT
    ([Standard_Payment_Plan], [Display_Order], [Is_Active])
    VALUES (src.[Standard_Payment_Plan], src.[Display_Order], src.[Is_Active]);
