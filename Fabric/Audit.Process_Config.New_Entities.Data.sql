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
