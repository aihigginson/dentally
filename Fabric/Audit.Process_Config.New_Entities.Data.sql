-- Add Rooms process config for all 8 tenants
-- Idempotent: skips rows that already exist
INSERT INTO Audit.Process_Config (Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code, Process_Type_Code)
SELECT v.Process_Code, v.Process_Name, v.Process_Desc, v.Process_Parameters, 'BRONZE', 'PROCEDURE'
FROM (VALUES
    ('BRONZE_T1_ROOMS',  'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 1 (live)',  '@Tenant_ID = 1,  @Full_Refresh = 0'),
    ('BRONZE_T2_ROOMS',  'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 2 (live)',  '@Tenant_ID = 2,  @Full_Refresh = 0'),
    ('BRONZE_T3_ROOMS',  'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 3 (live)',  '@Tenant_ID = 3,  @Full_Refresh = 0'),
    ('BRONZE_T4_ROOMS',  'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 4 (live)',  '@Tenant_ID = 4,  @Full_Refresh = 0'),
    ('BRONZE_T11_ROOMS', 'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 11 (dev)', '@Tenant_ID = 11, @Full_Refresh = 0'),
    ('BRONZE_T12_ROOMS', 'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 12 (dev)', '@Tenant_ID = 12, @Full_Refresh = 0'),
    ('BRONZE_T13_ROOMS', 'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 13 (dev)', '@Tenant_ID = 13, @Full_Refresh = 0'),
    ('BRONZE_T14_ROOMS', 'Bronze.usp_Load_Rooms', 'Bronze: Rooms for Tenant 14 (dev)', '@Tenant_ID = 14, @Full_Refresh = 0')
) AS v(Process_Code, Process_Name, Process_Desc, Process_Parameters)
WHERE NOT EXISTS (
    SELECT 1 FROM Audit.Process_Config pc WHERE pc.Process_Code = v.Process_Code
);
PRINT CONCAT('Rooms Process_Config rows inserted: ', @@ROWCOUNT);
GO

-- Add Dim_NHS_Contracts and Fact_NHS_Claims Gold process config
INSERT INTO Audit.Process_Config (Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code, Process_Type_Code)
SELECT v.Process_Code, v.Process_Name, v.Process_Desc, v.Process_Parameters, v.Process_Category_Code, 'PROCEDURE'
FROM (VALUES
    ('GOLD_DIM_NHS_CONTRACTS', 'Gold.usp_Load_Dim_NHS_Contracts', 'Load Gold.Dim_NHS_Contracts from Silver.Contracts', '@Mode = ''LIVE'', @Logging = 1', 'GOLD_DIM'),
    ('GOLD_FACT_NHS_CLAIMS',   'Gold.usp_Load_Fact_NHS_Claims',   'Load Gold.Fact_NHS_Claims from Silver.NHS_Claims',  '@Mode = ''LIVE'', @Logging = 1', 'GOLD_FACT')
) AS v(Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code)
WHERE NOT EXISTS (
    SELECT 1 FROM Audit.Process_Config pc WHERE pc.Process_Code = v.Process_Code
);
PRINT CONCAT('NHS Contracts/Claims Process_Config rows inserted: ', @@ROWCOUNT);
GO
