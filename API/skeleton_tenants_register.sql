/* ============================================================================
   DEV ONLY -- registration rows for the structural test tenants 21-24.

   ==> THIS MUST NEVER BE PUT IN A Releases/ MANIFEST. <== Scripts/Deploy.ps1 applies a
   manifest to whichever environment it is pointed at, and these rows would create four
   invented practices in the live warehouse. Test tenants are hand-inserted on DEV, which
   is why there is no manifest for them and no DDL file in Fabric/.

   Each tenant gets its OWN client, exactly as usp_Provision_Tenant would allocate --
   provisioning stays one tenant, one client, and the group is formed separately afterwards
   by Audit.usp_Form_Client_Group. Nothing here groups anything.

   Idempotent.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

/* SELECT ... INTO, not CREATE TABLE + INSERT VALUES: Fabric refuses the latter on a temp
   table with "an object that is not supported in distributed processing mode". */
DROP TABLE IF EXISTS #sk;
SELECT CAST(x.Tenant_ID AS INT) AS Tenant_ID, CAST(x.Name AS VARCHAR(100)) AS Name
INTO   #sk
FROM  (SELECT 21 AS Tenant_ID, 'Skeleton Alpha'   AS Name
       UNION ALL SELECT 22, 'Skeleton Bravo'
       UNION ALL SELECT 23, 'Skeleton Charlie'
       UNION ALL SELECT 24, 'Skeleton Delta') x;

/* ---- refuse to touch anything at or above 100 ---------------------------- */
IF EXISTS (SELECT 1 FROM #sk WHERE Tenant_ID >= 100)
    THROW 51300, 'Skeleton tenants must be below 100; 100+ are real practices.', 1;

/* ---- one client per tenant, as provisioning would ------------------------ */
INSERT INTO Security.Clients (Client_ID, Client_Name)
SELECT s.Tenant_ID, s.Name FROM #sk s
WHERE  NOT EXISTS (SELECT 1 FROM Security.Clients c WHERE c.Client_ID = s.Tenant_ID);

INSERT INTO Audit.Tenants
    (Tenant_ID, Client_ID, Tenant_Name, API_Base_URL, API_Key, Dentally_Client_ID,
     Dentally_Secret, Is_Active, Last_Loaded_At, Notes)
SELECT s.Tenant_ID, s.Tenant_ID, s.Name, 'https://api.dentally.co/v1', NULL, NULL, NULL,
       1, NULL, 'DEV structural test tenant for hierarchy roll-up work; synthetic data only'
FROM   #sk s
WHERE  NOT EXISTS (SELECT 1 FROM Audit.Tenants t WHERE t.Tenant_ID = s.Tenant_ID);

/* ---- the tenant can see itself, as provisioning would grant -------------- */
INSERT INTO Security.Client_Tenant_Access (Client_ID, Tenant_ID, Granted_At, Granted_By)
SELECT s.Tenant_ID, s.Tenant_ID, @now, 'skeleton:dev' FROM #sk s
WHERE  NOT EXISTS (SELECT 1 FROM Security.Client_Tenant_Access a
                   WHERE a.Client_ID = s.Tenant_ID AND a.Tenant_ID = s.Tenant_ID);

/* ---- and the vendor client sees everything, as it does for 11/12/100 ----- */
INSERT INTO Security.Client_Tenant_Access (Client_ID, Tenant_ID, Granted_At, Granted_By)
SELECT 1, s.Tenant_ID, @now, 'skeleton:dev' FROM #sk s
WHERE  NOT EXISTS (SELECT 1 FROM Security.Client_Tenant_Access a
                   WHERE a.Client_ID = 1 AND a.Tenant_ID = s.Tenant_ID);

SELECT t.Tenant_ID, CAST(t.Tenant_Name AS VARCHAR(20)) AS tenant, t.Client_ID AS owned_by,
       CAST(STRING_AGG(CAST(a.Client_ID AS VARCHAR(10)), ',') AS VARCHAR(20)) AS granted_to
FROM   Audit.Tenants t
LEFT JOIN Security.Client_Tenant_Access a ON a.Tenant_ID = t.Tenant_ID
WHERE  t.Tenant_ID IN (SELECT Tenant_ID FROM #sk)
GROUP BY t.Tenant_ID, t.Tenant_Name, t.Client_ID
ORDER BY t.Tenant_ID;
