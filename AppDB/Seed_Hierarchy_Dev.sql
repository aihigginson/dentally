-- Seed the client hierarchy for the tenants that exist today, as pass-throughs.
--
-- Every client gets exactly one Region and one Area, and every site is placed in its
-- client's Area. That is the degenerate shape on purpose: the hiding rule then suppresses
-- all of it, so nothing a customer sees changes, while the structure is present and real.
--
-- Idempotent. Re-running inserts nothing new.

-- ---- clients ------------------------------------------------------------------------
MERGE Input.Client AS tgt
USING (VALUES (1, 'Analytically'), (11, 'Demonstration Practice'), (100, 'Maple Dental'))
      AS src (Client_ID, Client_Name)
   ON tgt.Client_ID = src.Client_ID
WHEN NOT MATCHED THEN INSERT (Client_ID, Client_Name, Updated_By)
     VALUES (src.Client_ID, src.Client_Name, 'seed');

-- ---- which client each tenant belongs to ----------------------------------------------
-- Tenants 11 and 12 BOTH belong to client 11: the demo client already runs two practices,
-- one of them with two sites. That makes it the only real multi-practice shape available
-- for testing the hierarchy.
MERGE Input.Client_Tenant AS tgt
USING (VALUES (11, 11), (12, 11), (100, 100)) AS src (Tenant_ID, Client_ID)
   ON tgt.Tenant_ID = src.Tenant_ID
WHEN NOT MATCHED THEN INSERT (Tenant_ID, Client_ID, Updated_By)
     VALUES (src.Tenant_ID, src.Client_ID, 'seed');

-- ---- one region per client -------------------------------------------------------------
INSERT INTO Input.Client_Region (Client_ID, Region_Name, Updated_By)
SELECT c.Client_ID, 'All', 'seed'
FROM   Input.Client c
WHERE  NOT EXISTS (SELECT 1 FROM Input.Client_Region r WHERE r.Client_ID = c.Client_ID);

-- ---- one area per region ---------------------------------------------------------------
INSERT INTO Input.Client_Area (Region_ID, Area_Name, Updated_By)
SELECT r.Region_ID, 'All', 'seed'
FROM   Input.Client_Region r
WHERE  NOT EXISTS (SELECT 1 FROM Input.Client_Area a WHERE a.Region_ID = r.Region_ID);

-- ---- place every site in its client's area ----------------------------------------------
-- The site list comes from the warehouse, so it is typed out here rather than joined. A
-- later admin screen replaces this entirely; for now it is how dev gets a complete tree.
MERGE Input.Site_Area AS tgt
USING (VALUES (11,  't11-cl'),
              (12,  't12-gt'),
              (12,  't12-sb'),
              (100, '027ed563-acef-4734-bdc9-40e4330347f3'))
      AS src (Tenant_ID, Site_ID)
   ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Site_ID = src.Site_ID
WHEN NOT MATCHED THEN INSERT (Tenant_ID, Site_ID, Area_ID, Updated_By)
     VALUES (src.Tenant_ID, src.Site_ID,
             (SELECT TOP 1 a.Area_ID
              FROM   Input.Client_Area a
              JOIN   Input.Client_Region r  ON r.Region_ID = a.Region_ID
              JOIN   Input.Client_Tenant ct ON ct.Client_ID = r.Client_ID
              WHERE  ct.Tenant_ID = src.Tenant_ID
              ORDER BY a.Area_ID),
             'seed');

-- ---- what the tree now looks like ---------------------------------------------------
SELECT c.Client_ID, c.Client_Name, r.Region_Name, a.Area_Name,
       sa.Tenant_ID, sa.Site_ID
FROM   Input.Client c
LEFT JOIN Input.Client_Region r ON r.Client_ID = c.Client_ID
LEFT JOIN Input.Client_Area   a ON a.Region_ID = r.Region_ID
LEFT JOIN Input.Site_Area    sa ON sa.Area_ID  = a.Area_ID
ORDER BY c.Client_ID, sa.Tenant_ID, sa.Site_ID;

-- ---- the degeneracy rule, run against the seeded data ---------------------------------
-- A level is hidden when every node at it has exactly one child. This is the query the UI
-- will ask; here it proves the seed produces the expected answer for each client.
SELECT c.Client_Name,
       COUNT(DISTINCT r.Region_ID)                     AS regions,
       COUNT(DISTINCT a.Area_ID)                       AS areas,
       COUNT(DISTINCT sa.Tenant_ID)                    AS practices,
       COUNT(DISTINCT CAST(sa.Tenant_ID AS VARCHAR(12)) + ':' + sa.Site_ID) AS sites
FROM   Input.Client c
LEFT JOIN Input.Client_Region r ON r.Client_ID = c.Client_ID
LEFT JOIN Input.Client_Area   a ON a.Region_ID = r.Region_ID
LEFT JOIN Input.Site_Area    sa ON sa.Area_ID  = a.Area_ID
GROUP BY c.Client_Name
ORDER BY c.Client_Name;
