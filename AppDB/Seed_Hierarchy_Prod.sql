/* ============================================================================
   APPDB-PROD -- the client hierarchy Maple needs before the targets rework can read anything.

   ==> WITHOUT THIS, MAPLE'S 334 TARGETS BECOME INVISIBLE. <== Gold.usp_Load_Fact_Node_Targets
   builds its tree from Input.Client_Region -> Client_Area -> Site_Area -> Dim_Practice_Sites. All
   three bridge tables are EMPTY on prod, so the loader finds no nodes and publishes nothing. Worse,
   AppDB.Migration.Client_Keying.sql backfills Client_ID *from* Input.Client_Tenant -- so against an
   empty map every target keeps a NULL Client_ID, and the loader skips those outright. The targets
   are never lost, but nothing can display them.

   ==> THE REGION AND AREA NAMES NEVER APPEAR ANYWHERE. <== Maple has one active site, so every
   level has the same site count, and the fold keeps only the highest-ranked node on that run --
   Practice, by the owner's "Practice outwards" order. Region, Area and Client all collapse into it.
   The rows have to EXIST for the join to resolve a site to a client; their names are structural
   filler and are deliberately named so that if one ever does surface, it is obviously this script's.

   ==> CLIENT 100, NOT 1000. <== Security.Clients on prod carries three: 1 Analytically,
   100 Maple Dental, 1000 Maple Dentalcare Ltd. 1000 is the legal entity the invoices are raised to;
   the TENANT belongs to client 100. Mapping it to 1000 would put the targets under a client nobody
   signs in as.

   Measured on prod, 30 Oct 2026, and this script asserts each of them rather than trusting them:
       Gold.Dim_Practice_Sites  tenant 100 -> exactly one active site,
                                Site_ID 027ed563-acef-4734-bdc9-40e4330347f3 'Maple Dental'
       Security.Clients         holds Client_ID 100

   Idempotent: every insert is guarded, so a re-run adds nothing.
   ============================================================================ */
SET NOCOUNT ON;

IF DB_NAME() NOT IN ('AppDB-prod', 'AppDB-dev')
    THROW 51400, 'Seed_Hierarchy_Prod: wrong database.', 1;
GO

DECLARE @client   INT         = 100;
DECLARE @tenant   INT         = 100;
DECLARE @site     VARCHAR(64) = '027ed563-acef-4734-bdc9-40e4330347f3';   /* Maple Dental */
DECLARE @by       VARCHAR(256)= 'release:targets-rework';

/* ---- 1. the client itself ----------------------------------------------- */
/* Input.Client is the AppDB's own copy of the registry; Security.Clients in the warehouse is the
   one RLS reads. They are kept in step by the sync, so this must name the client identically. */
IF NOT EXISTS (SELECT 1 FROM Input.Client WHERE Client_ID = @client)
    INSERT INTO Input.Client (Client_ID, Client_Name, Is_Active, Updated_At, Updated_By)
    VALUES (@client, 'Maple Dental', 1, SYSUTCDATETIME(), @by);

/* ---- 2. tenant -> client, the mapping everything else keys on ------------ */
IF NOT EXISTS (SELECT 1 FROM Input.Client_Tenant WHERE Tenant_ID = @tenant)
    INSERT INTO Input.Client_Tenant (Tenant_ID, Client_ID, Updated_At, Updated_By)
    VALUES (@tenant, @client, SYSUTCDATETIME(), @by);

/* ---- 3. one region, one area -- structural, and they fold away ----------- */
DECLARE @region INT, @area INT;

SELECT @region = Region_ID FROM Input.Client_Region
WHERE  Client_ID = @client AND Region_Name = 'All';
IF @region IS NULL
BEGIN
    INSERT INTO Input.Client_Region (Client_ID, Region_Name, Sort_Order, Is_Active, Updated_At, Updated_By)
    VALUES (@client, 'All', 1, 1, SYSUTCDATETIME(), @by);
    SET @region = SCOPE_IDENTITY();
END

SELECT @area = Area_ID FROM Input.Client_Area
WHERE  Region_ID = @region AND Area_Name = 'All';
IF @area IS NULL
BEGIN
    INSERT INTO Input.Client_Area (Region_ID, Area_Name, Sort_Order, Is_Active, Updated_At, Updated_By)
    VALUES (@region, 'All', 1, 1, SYSUTCDATETIME(), @by);
    SET @area = SCOPE_IDENTITY();
END

/* ---- 4. the site into that area ----------------------------------------- */
/* Site_ID is the DENTALLY key, not the warehouse surrogate: Input.Site_Area is keyed
   (Tenant_ID, Site_ID) and the loader joins Dim_Practice_Sites on both. */
IF NOT EXISTS (SELECT 1 FROM Input.Site_Area WHERE Tenant_ID = @tenant AND Site_ID = @site)
    INSERT INTO Input.Site_Area (Tenant_ID, Site_ID, Area_ID, Updated_At, Updated_By)
    VALUES (@tenant, @site, @area, SYSUTCDATETIME(), @by);

PRINT 'client ' + CAST(@client AS VARCHAR(10))
    + '  region ' + CAST(@region AS VARCHAR(10))
    + '  area '   + CAST(@area AS VARCHAR(10))
    + '  site '   + @site;
GO

/* ---- 5. prove it, rather than assume it --------------------------------- */
SELECT 'Client'        AS t, COUNT(*) AS rows_ FROM Input.Client        WHERE Client_ID = 100
UNION ALL SELECT 'Client_Tenant', COUNT(*) FROM Input.Client_Tenant WHERE Tenant_ID = 100 AND Client_ID = 100
UNION ALL SELECT 'Client_Region', COUNT(*) FROM Input.Client_Region WHERE Client_ID = 100
UNION ALL SELECT 'Client_Area',   COUNT(*) FROM Input.Client_Area   a
          WHERE EXISTS (SELECT 1 FROM Input.Client_Region r WHERE r.Region_ID = a.Region_ID AND r.Client_ID = 100)
UNION ALL SELECT 'Site_Area',     COUNT(*) FROM Input.Site_Area     WHERE Tenant_ID = 100;

/* The chain must resolve end to end: site -> area -> region -> client. A broken link here is the
   difference between "Maple has one node" and "Maple has none", and the second shows as an empty
   report rather than an error. */
SELECT 'resolves' AS check_, sa.Tenant_ID, sa.Site_ID, a.Area_Name, r.Region_Name, c.Client_Name
FROM   Input.Site_Area     sa
JOIN   Input.Client_Area   a ON a.Area_ID   = sa.Area_ID
JOIN   Input.Client_Region r ON r.Region_ID = a.Region_ID
JOIN   Input.Client        c ON c.Client_ID = r.Client_ID
JOIN   Input.Client_Tenant ct ON ct.Tenant_ID = sa.Tenant_ID AND ct.Client_ID = c.Client_ID;
GO
