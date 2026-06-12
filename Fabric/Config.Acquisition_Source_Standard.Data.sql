-- Seed data for Config.Acquisition_Source_Standard
MERGE [Config].[Acquisition_Source_Standard] AS tgt
USING (VALUES
    ('Word of Mouth',     1,  1),
    ('Online Search',     2,  1),
    ('Social Media',      3,  1),
    ('Walk In',           4,  1),
    ('Internal Referral', 5,  1),
    ('External Referral', 6,  1),
    ('Advertisement',     7,  1),
    ('Other',             99, 1)
) AS src ([Standard_Acquisition_Source], [Display_Order], [Is_Active])
ON tgt.[Standard_Acquisition_Source] = src.[Standard_Acquisition_Source]
WHEN MATCHED THEN UPDATE SET
    [Display_Order] = src.[Display_Order],
    [Is_Active]     = src.[Is_Active]
WHEN NOT MATCHED BY TARGET THEN INSERT
    ([Standard_Acquisition_Source], [Display_Order], [Is_Active])
    VALUES (src.[Standard_Acquisition_Source], src.[Display_Order], src.[Is_Active]);
