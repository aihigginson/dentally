-- Seed data for Config.Treatment_Category_Standard
-- Tune categories to match reporting needs. Is_Active = 0 hides from dropdowns without deleting.
MERGE [Config].[Treatment_Category_Standard] AS tgt
USING (VALUES
    ('Examination',         1,  1),
    ('Hygiene & Prevention',2,  1),
    ('Restorative',         3,  1),
    ('Endodontics',         4,  1),
    ('Periodontics',        5,  1),
    ('Oral Surgery',        6,  1),
    ('Orthodontics',        7,  1),
    ('Prosthodontics',      8,  1),
    ('Implants',            9,  1),
    ('Cosmetic',            10, 1),
    ('NHS',                 11, 1),
    ('Other',               99, 1)
) AS src ([Standard_Treatment_Category], [Display_Order], [Is_Active])
ON tgt.[Standard_Treatment_Category] = src.[Standard_Treatment_Category]
WHEN MATCHED THEN UPDATE SET
    [Display_Order] = src.[Display_Order],
    [Is_Active]     = src.[Is_Active]
WHEN NOT MATCHED BY TARGET THEN INSERT
    ([Standard_Treatment_Category], [Display_Order], [Is_Active])
    VALUES (src.[Standard_Treatment_Category], src.[Display_Order], src.[Is_Active]);
